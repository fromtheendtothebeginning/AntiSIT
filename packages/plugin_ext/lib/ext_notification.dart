import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 拓展通知的宿主实现：拓展声明 `notification` 权限后可用 `ctx.notify.*` 发本地通知。
///
/// 渠道与上课提醒分开（`ext_notify`），`cancelAll()` 只清这条拓展自己排过的通知；
/// id 走 0x40000000 以上区间，避开上课提醒的 30 位哈希。
abstract class ExtNotificationService {
  /// 测试可以换成假实现（不碰系统通知）。
  static ExtNotificationService instance = PlatformExtNotificationService();

  /// 立即弹一条。[key] 相同会覆盖上一条；为空时按当前时刻生成。
  /// [popup] 为 true 时走高优先级「弹窗」渠道（会弹横幅），需要用户运行时确认。
  Future<void> show({
    required String extId,
    String? key,
    required String title,
    String? body,
    bool popup = false,
  });

  /// 到点再弹，App 没开也能收到（系统闹钟拉起）。
  /// [popup] 为 true 时走高优先级「弹窗」渠道（到点弹横幅）。
  Future<void> schedule({
    required String extId,
    required String key,
    required String title,
    String? body,
    required DateTime at,
    bool popup = false,
  });

  /// 撤掉一条（按拓展作者给的 key）。
  Future<void> cancel({required String extId, required String key});

  /// 撤掉这条拓展排过的全部通知。
  Future<void> cancelAll({required String extId});
}

/// 真机实现：flutter_local_notifications + 按拓展隔离的 id 记录。
class PlatformExtNotificationService implements ExtNotificationService {
  static const String _channelId = 'ext_notify';
  static const String _channelName = '拓展通知';
  static const String _channelDesc = '拓展发来的提醒与消息';

  /// 弹窗通知单独一个渠道：高重要级才会在屏幕上弹横幅；渠道建好后重要级不能再升，
  /// 所以不能和普通的 `ext_notify` 共用。
  static const String _popupChannelId = 'ext_popup';
  static const String _popupChannelName = '拓展弹窗';
  static const String _popupChannelDesc = '拓展发来的弹窗提醒（屏幕横幅）';

  /// notification id 高位：避开上课提醒的哈希区间（< 2^30）。
  static const int _idBase = 0x40000000;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initFuture;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static const NotificationDetails _popupDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _popupChannelId,
      _popupChannelName,
      channelDescription: _popupChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      playSound: true,
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
  );

  @override
  Future<void> show({
    required String extId,
    String? key,
    required String title,
    String? body,
    bool popup = false,
  }) async {
    final id = _idFor(extId, key ?? 'show:${DateTime.now().microsecondsSinceEpoch}');
    await _ensureReady();
    await _ensurePermission();
    await _plugin.show(id, title, body, popup ? _popupDetails : _details);
    await _remember(extId, id);
  }

  @override
  Future<void> schedule({
    required String extId,
    required String key,
    required String title,
    String? body,
    required DateTime at,
    bool popup = false,
  }) async {
    final id = _idFor(extId, key);
    await _ensureReady();
    await _ensurePermission();
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(at, tz.local),
      popup ? _popupDetails : _details,
      androidScheduleMode: await _scheduleMode(),
    );
    await _remember(extId, id);
  }

  @override
  Future<void> cancel({required String extId, required String key}) async {
    final id = _idFor(extId, key);
    await _ensureReady();
    await _plugin.cancel(id);
    await _forget(extId, id);
  }

  @override
  Future<void> cancelAll({required String extId}) async {
    final ids = await _remembered(extId);
    if (ids.isEmpty) return;
    await _ensureReady();
    for (final id in ids) {
      await _plugin.cancel(id);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_idsKey(extId));
  }

  Future<void> _ensureReady() async {
    final pending = _initFuture ??= _init();
    try {
      await pending;
    } catch (_) {
      _initFuture = null; // 失败别把毒化的 Future 留着，下次重试
      rethrow;
    }
  }

  Future<void> _init() async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      throw ArgumentError('当前平台不支持通知');
    }
    tzdata.initializeTimeZones();
    tz.setLocalLocation(_localLocation());
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      // 权限在第一次真正发通知时再要，不给拓展「一打开就弹系统框」
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ));
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.defaultImportance,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _popupChannelId,
      _popupChannelName,
      description: _popupChannelDesc,
      importance: Importance.high,
    ));
  }

  /// 第一次调用时申请系统通知权限（Android 13+ / iOS 都需要）。
  Future<void> _ensurePermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      var enabled = await android?.areNotificationsEnabled() ?? false;
      if (!enabled) {
        enabled = await android?.requestNotificationsPermission() ?? false;
      }
      if (!enabled) {
        throw ArgumentError('通知权限未允许：请在系统设置里允许 AntiSIT 发送通知');
      }
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final current = await ios?.checkPermissions();
      if (current?.isEnabled == true) return;
      final granted = await ios?.requestPermissions(alert: true, badge: true, sound: true);
      if (granted != true) {
        throw ArgumentError('通知权限未允许：请在系统设置里允许 AntiSIT 发送通知');
      }
    }
  }

  /// 精确闹钟没授权就用不精确的（差几分钟，但通知能到）。
  /// 不像上课提醒那样主动弹「去授权」——拓展通知不应该把用户拽去系统设置。
  Future<AndroidScheduleMode> _scheduleMode() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (await android?.canScheduleExactNotifications() == true) {
        return AndroidScheduleMode.exactAllowWhileIdle;
      }
    } catch (_) {}
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// 本机时区：与上课提醒同一套兜底（设备时区名 → 偏移量匹配 → UTC）。
  static tz.Location _localLocation() {
    final name = DateTime.now().timeZoneName;
    for (final candidate in [name, if (name == 'CST') 'Asia/Shanghai']) {
      try {
        return tz.getLocation(candidate);
      } catch (_) {}
    }
    final offset = DateTime.now().timeZoneOffset;
    for (final location in tz.timeZoneDatabase.locations.values) {
      if (location.currentTimeZone.offset == offset.inMilliseconds) return location;
    }
    return tz.getLocation('UTC');
  }

  static int _idFor(String extId, String key) {
    var hash = 17;
    for (final unit in '$extId|$key'.codeUnits) {
      hash = (hash * 31 + unit) & 0x3fffffff;
    }
    return _idBase | hash;
  }

  static String _idsKey(String extId) => 'plugin.ext.notify.ids.$extId';

  static Future<Set<int>> _remembered(String extId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_idsKey(extId)) ?? const <String>[];
    return {for (final s in raw) if (int.tryParse(s) != null) int.parse(s)};
  }

  static Future<void> _remember(String extId, int id) async {
    final ids = await _remembered(extId);
    ids.add(id);
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_idsKey(extId), [for (final i in ids) '$i']);
  }

  static Future<void> _forget(String extId, int id) async {
    final ids = await _remembered(extId);
    ids.remove(id);
    final sp = await SharedPreferences.getInstance();
    if (ids.isEmpty) {
      await sp.remove(_idsKey(extId));
    } else {
      await sp.setStringList(_idsKey(extId), [for (final i in ids) '$i']);
    }
  }
}
