import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'ext_foreground_notice.dart';

/// 拓展通知的宿主实现：市场拓展声明 `notification` 权限后，可以用
/// `ctx.notify.show / schedule / cancel / cancelAll` 发本地通知。
///
/// 渠道与上课提醒分开（`ext_notify`），取消也按 id 逐条撤——`cancelAll()` 只清
/// 这条拓展自己排过的通知，不会误伤课表提醒。id 走 0x40000000 以上的区间，
/// 避开上课提醒的 30 位哈希。
///
/// **前台 vs 后台是两条路**（用户报过「切后台能收到、开着 App 反而收不到」）：
/// Android 对应用自己在**前台**时发的横幅通知做了压制，通知只进通知栏不弹屏幕。
/// 所以 [show] 在 App 前台时先走 [ExtForegroundNotice] 的页内横幅，系统通知照发
/// 但不响（静音），通知栏里留一条档；退到后台就只剩系统通知那条路——定时通知
/// （[schedule]，由系统闹钟拉起）本来就是后台场景，不受影响。
abstract class ExtNotificationService {
  /// 测试可以换成假实现（不碰系统通知）。
  static ExtNotificationService instance = PlatformExtNotificationService();

  /// 立即弹一条。[key] 相同会覆盖上一条；为空时按当前时刻生成。
  /// [popup] 为 true 时走高优先级「弹窗」渠道（会弹横幅），需要用户运行时确认。
  /// [extName] 只用于前台横幅上那行小字（谁发的）；不给就用 id。
  Future<void> show({
    required String extId,
    String? extName,
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

  /// App 回到前台时调一次：定时通知到点时系统通知栏会亮，但 Android 会压掉
  /// 前台应用的横幅，需要靠巡检补一条页内横幅。默认什么也不做（测试用的假实现）。
  void watchForeground() {}

  /// 拓展 id → 显示名：前台横幅上那行小字用。宿启动时注入（见 `ExtPlugin.init`），
  /// 拿不到就退回 id——不为了一个标签让通知模块去依赖拓展清单（会绕成循环）。
  static String Function(String extId)? extNameResolver;

  /// 解析显示名；解析不出来返回空串（横幅就不显示那一行）。
  static String displayNameOf(String extId) {
    if (extId.isEmpty) return '';
    try {
      return (extNameResolver?.call(extId) ?? '').trim();
    } catch (_) {
      return '';
    }
  }
}

/// 真机实现：flutter_local_notifications + 按拓展隔离的 id 记录。
class PlatformExtNotificationService
    with WidgetsBindingObserver
    implements ExtNotificationService {
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

  /// 前台巡检：定时通知由系统闹钟在**进程外**拉起，发出来的那一刻我们并不知道。
  /// 而 Android 会压掉前台应用的横幅，所以「App 开着的时候到点」就成了用户说的
  /// 收不到。这里在前台时每隔几秒查一次通知栏，把新出现的拓展通知补一条页内横幅。
  static const Duration _watchInterval = Duration(seconds: 4);
  Timer? _watchTimer;
  bool _watching = false;

  /// 上一轮巡检看到的通知 id：只有**新出现**的才补横幅，刷新同一条不会反复弹。
  Set<int> _seen = <int>{};

  /// 刚由 [show] 在前台发过的 id（时刻）：那条已经有横幅了，巡检别再弹一次。
  final Map<int, DateTime> _selfShown = <int, DateTime>{};

  /// 通知 id → 拓展 id（横幅上要显示「谁发的」，也用于同一条去重）。
  final Map<int, String> _owner = <int, String>{};

  /// 横幅上「谁发的」那一行：调用方给了名字就用，没给就查拓展清单，再没有就不显示。
  static String? _sourceLabel(String extId, String? extName) {
    final given = (extName ?? '').trim();
    if (given.isNotEmpty) return given;
    final resolved = ExtNotificationService.displayNameOf(extId);
    return resolved.isEmpty ? null : resolved;
  }

  /// 是否已经把 [WidgetsBinding] 的观察者挂上（只挂一次）。
  bool _observing = false;

  /// [_owners] 的短时缓存（巡检每几秒一次，别反复读偏好）。
  ({DateTime at, Map<int, String> byId})? _ownersCache;

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

  /// App 在前台时发的那份系统通知：**静音**。屏幕上的提示交给页内横幅
  /// （[ExtForegroundNotice]），系统这份只为了让通知栏留档，别再响一次。
  ///
  /// 用哪个渠道跟 popup 走：弹窗提醒本来就该落在「拓展弹窗」这条高优先级渠道里，
  /// 用户去通知栏翻的时候也在同一组。
  static NotificationDetails _silentDetails({required bool popup}) => NotificationDetails(
        android: AndroidNotificationDetails(
          popup ? _popupChannelId : _channelId,
          popup ? _popupChannelName : _channelName,
          channelDescription: popup ? _popupChannelDesc : _channelDesc,
          importance: popup ? Importance.high : Importance.defaultImportance,
          priority: popup ? Priority.high : Priority.defaultPriority,
          category: AndroidNotificationCategory.reminder,
          silent: true,
          onlyAlertOnce: true,
        ),
        iOS: const DarwinNotificationDetails(presentAlert: false, presentSound: false),
      );

  @override
  Future<void> show({
    required String extId,
    String? extName,
    String? key,
    required String title,
    String? body,
    bool popup = false,
  }) async {
    final id = _idFor(extId, key ?? 'show:${DateTime.now().microsecondsSinceEpoch}');
    // 前台先把页内横幅弹出来：Android 会压掉前台应用自己发的横幅通知，
    // 只发系统通知就等于「用户正看着 App 的时候什么都收不到」。
    final inApp = ExtForegroundNotice.I.show(
      extId: extId,
      title: title,
      body: body,
      key: key,
      source: _sourceLabel(extId, extName),
    );
    await _ensureReady();
    try {
      await _ensurePermission();
    } catch (_) {
      // 系统通知权限没给（或系统框弹不出来）：页内横幅已经弹过了，这次调用不算失败。
      // 早先这里直接抛错，插件以为「弹窗不可用」就把自己的开关关掉了。
      if (!inApp) rethrow;
      _owner[id] = extId;
      unawaited(_startWatch());
      return;
    }
    await _plugin.show(
      id,
      title,
      body,
      inApp
          ? _silentDetails(popup: popup)
          : (popup ? _popupDetails : _details),
    );
    // 巡检那边马上会看到这条通知：记一笔，别在前台又补弹一条横幅
    if (inApp) _selfShown[id] = DateTime.now();
    _owner[id] = extId;
    // App 开着：把巡检挂上，到点的定时通知也能补横幅（见 [_startWatch]）
    unawaited(_startWatch());
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
    _owner[id] = extId;
    // 有排期了：把巡检挂上——到点那一刻如果 App 正好开着，靠它补页内横幅
    if (ExtForegroundNotice.I.inForeground) unawaited(_startWatch());
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

  // ==================== 初始化 / 权限 ====================

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

  // ==================== 前台巡检（到点的定时通知补横幅）====================

  /// 挂上前台巡检。App 退到后台时自动停表（后台靠系统通知，不需要巡检）。
  ///
  /// 幂等：已经挂过但表停着（没有排期时自己停的）就只把表续上，不重复取基线。
  Future<void> _startWatch() async {
    if (_watching) {
      if (_watchTimer == null && ExtForegroundNotice.I.inForeground) _restartTimer();
      return;
    }
    _watching = true;
    if (!_observing) {
      try {
        WidgetsBinding.instance.addObserver(this);
        _observing = true;
      } catch (_) {
        // 测试 / 没有 binding：巡检照跑，只是不跟生命周期联动
      }
    }
    // 拿一次基线：只对「之后新出现」的通知补横幅，不然一开 App 就把通知栏刷一遍
    try {
      final active = await _activeExt();
      _seen = {for (final n in active) if (n.id != null) n.id!};
    } catch (_) {
      _seen = <int>{};
    }
    _restartTimer();
  }

  void _restartTimer() {
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(_watchInterval, (_) => unawaited(_checkActive()));
  }

  /// 回前台续上巡检、退后台停表（后台有系统通知，巡检只会白耗电）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_watching) _restartTimer();
    } else {
      _watchTimer?.cancel();
      _watchTimer = null;
    }
  }

  /// 还有没有「已排好、还没到点」的拓展通知。没有就不用巡检了。
  Future<bool> _hasPending() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return pending.any((p) => _isExtId(p.id));
    } catch (_) {
      return true; // 查不出来就当有，宁可多巡检也别漏掉提醒
    }
  }

  /// 通知栏里现在有哪些「拓展通知」（只看 id 落在我们高位区间里的）。
  Future<List<ActiveNotification>> _activeExt() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return const <ActiveNotification>[];
    final active = await android.getActiveNotifications();
    return [
      for (final n in active)
        if (n.id != null && _isExtId(n.id!)) n,
    ];
  }

  /// 巡检一轮：新冒出来的拓展通知补一条页内横幅。
  ///
  /// 这条路径专治「App 开着的时候到点不弹」：定时通知由系统闹钟在进程外拉起，
  /// 它出现在通知栏的那一刻没有任何 Dart 回调，只能靠这里捞出来再画一条横幅。
  ///
  /// 没有任何排期时就停表——巡检只在「可能有通知冒出来」的窗口里跑，不白耗电。
  Future<void> _checkActive() async {
    if (!ExtForegroundNotice.I.inForeground) return;
    final List<ActiveNotification> active;
    try {
      active = await _activeExt();
    } catch (_) {
      return; // 查询失败（旧内核 / 通道异常）：这一轮跳过，不打扰
    }
    if (active.isEmpty && !await _hasPending()) {
      _watchTimer?.cancel();
      _watchTimer = null;
      return;
    }
    final owners = await _owners();
    final now = DateTime.now();
    for (final n in active) {
      final id = n.id!;
      if (_seen.contains(id)) continue;
      // 刚由 show() 在前台发的：横幅已经弹过，别重复
      final at = _selfShown[id];
      if (at != null && now.difference(at) < const Duration(seconds: 20)) continue;
      final title = (n.title ?? '').trim();
      if (title.isEmpty) continue;
      final extId = owners[id] ?? _owner[id] ?? '';
      final name = ExtNotificationService.displayNameOf(extId);
      ExtForegroundNotice.I.show(
        extId: extId,
        title: title,
        body: n.body,
        key: 'id:$id',
        source: name.isEmpty ? null : name,
      );
    }
    _seen = {for (final n in active) n.id!};
    _selfShown.removeWhere((_, at) => now.difference(at) > const Duration(minutes: 2));
  }

  /// 通知 id → 拓展 id：从各拓展的已排记录（`plugin.ext.notify.ids.<extId>`）反查。
  ///
  /// 巡检每几秒跑一次，别每次都读一遍偏好：结果缓存半分钟，排期改动本来也不频繁。
  Future<Map<int, String>> _owners() async {
    final cached = _ownersCache;
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(seconds: 30)) {
      return cached.byId;
    }
    final sp = await SharedPreferences.getInstance();
    final out = <int, String>{};
    const prefix = 'plugin.ext.notify.ids.';
    for (final key in sp.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      final extId = key.substring(prefix.length);
      for (final s in sp.getStringList(key) ?? const <String>[]) {
        final id = int.tryParse(s);
        if (id != null) out[id] = extId;
      }
    }
    _ownersCache = (at: DateTime.now(), byId: out);
    return out;
  }

  /// 是不是「拓展通知」的 id 区间。上课提醒 / 流体云 / 后台常驻通知都在这之外。
  static bool _isExtId(int id) => id >= _idBase && id < 0x80000000;

  /// App 回到前台时调一次：把巡检挂上（幂等）。拓展页打开时也会自动挂上，
  /// 这里是给「App 启动就回前台、但还没人发过通知」的情况补一刀。
  @override
  void watchForeground() {
    if (_watching) {
      if (_watchTimer == null) _restartTimer();
      return;
    }
    unawaited(_startWatch());
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

  // ==================== id 与已排记录 ====================

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
