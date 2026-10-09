import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../timetable_store.dart';
import 'plugins/plugin.dart';
import 'plugins/registry.dart';

/// 「上课提醒」插件的 id（见 lib/plugins/features/reminder_plugin.dart）。
/// 用字面量而不是 import 插件文件：插件可删，服务是基础设施。
/// 用户下课时表页要用它判断「提醒按钮该不该出现」，所以是公开的。
const String reminderPluginId = PluginIds.reminder;

/// 一条待排期的上课提醒（纯数据，便于单测）。
@immutable
class ClassReminder {
  const ClassReminder({required this.id, required this.course, required this.at});

  final int id; // 通知 id（按课次去重、稳定）
  final TtCourse course;
  final DateTime at; // 15 分钟前的本机时刻

  @override
  bool operator ==(Object other) => other is ClassReminder && other.id == id && other.at == at;

  @override
  int get hashCode => Object.hash(id, at);
}

/// 上课提醒：把课表里的每节课换算成「上课前 N 分钟」的本地定时通知。
///
/// 为什么用本地通知而不是后台轮询：定时通知由系统闹钟（AlarmManager）在到点时拉起，
/// App 被杀掉 / 在后台 / 没联网都能弹；进程内定时器做不到这一点。
/// 排期在每次打开 App、课表改动后重排（未来的课是有限的，重排即幂等覆盖）；
/// 重启后由 ScheduledNotificationBootReceiver 恢复（清单里已声明）。
class ClassReminderService extends ChangeNotifier {
  ClassReminderService._();
  static final ClassReminderService I = ClassReminderService._();

  static const String _spKey = 'class_reminder_on';
  static const String _channelId = 'class_reminder';
  static const String _channelName = '上课提醒';
  static const String _channelDesc = '课程开始前提醒';

  /// 提前分钟数（需求：上课前 15 分钟）。
  static const int leadMinutes = 15;

  /// 一次最多排多少条（每学期 20 周 × 每周若干节，够覆盖未来一个多月；避免排期过多）。
  static const int maxScheduled = 64;

  /// 排期最远看多少天（超出不排，下次打开 App 再补）。
  static const int horizonDays = 30;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _enabled = false;
  bool _ready = false;

  bool get enabled => _enabled;

  /// 记忆开关集中放这里（只有通知一件事要存），避免动 AppState 的持久化结构。
  Future<void> loadEnabled() async {
    final sp = await SharedPreferences.getInstance();
    _enabled = sp.getBool(_spKey) ?? false;
  }

  Future<void> _setEnabled(bool v) async {
    _enabled = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_spKey, v);
    notifyListeners();
  }

  // ==================== 纯计算：课表 → 提醒时刻 ====================

  /// 单次课的开始时刻（含日期）。[startDate] 为第 1 周周一（yyyy-MM-dd）。
  static DateTime? classStart(String startDate, int week, TtCourse c) {
    final start = DateTime.tryParse(startDate);
    if (start == null) return null;
    final day = dateOfWeekWeek(start, week, c.day);
    final hhmm = classStartMinutes(c);
    return day.add(Duration(minutes: hhmm));
  }

  static DateTime dateOfWeekWeek(DateTime startDate, int week, int dayIndex) =>
      DateTime(startDate.year, startDate.month, startDate.day)
          .add(Duration(days: (week - 1) * 7 + dayIndex));

  /// 该课在第 [week] 周是否开课（周次范围 + 单双周）。
  static bool meetsIn(TtCourse c, int week) {
    if (week < c.weekStart || week > c.weekEnd) return false;
    return switch (c.weekType) {
      'odd' => week.isOdd,
      'even' => week.isEven,
      _ => true,
    };
  }

  static int classStartMinutes(TtCourse c) => _slotStartMinutes[c.slotStart.clamp(0, 10)];

  /// 与课表页一致的 11 节上课时刻（分钟）。
  static const List<int> _slotStartMinutes = [
    8 * 60 + 20, 9 * 60 + 10, 10 * 60 + 10, 11 * 60, 13 * 60,
    13 * 60 + 50, 14 * 60 + 55, 15 * 60 + 45, 18 * 60, 18 * 60 + 50, 19 * 60 + 40,
  ];

  /// 生成 [from, from+horizonDays) 内所有未到期的提醒，按时间升序，最多 [maxScheduled] 条。
  /// [store] 里每个学期都算（同一节课被多学期收录时按「名称+时刻」去重）。
  ///
  /// 排期按**调休规则换算后的实际上课日**走（与课表页渲染同一套规则）：
  /// off 的那天不排（放假不该提醒），follow 的那天按被借星期的课表排
  /// （周六补周二的课，提醒的当然是周二那几门）。
  static List<ClassReminder> plan(
    TimetableStore store,
    DateTime from, {
    int leadMinutes = ClassReminderService.leadMinutes,
    int horizonDays = ClassReminderService.horizonDays,
    int maxScheduled = ClassReminderService.maxScheduled,
  }) {
    final until = from.add(Duration(days: horizonDays));
    final out = <ClassReminder>[];
    final seen = <String>{};
    for (final tt in store.semesters.values) {
      final start = DateTime.tryParse(tt.startDate);
      if (start == null || tt.weekCount <= 0) continue;
      final courses = TimetableStore.deriveImported(tt).followedBy(tt.courses).toList();
      for (var w = 1; w <= tt.weekCount; w++) {
        for (var di = 0; di < 7; di++) {
          // 这一天实际按星期几的课表上课；放假（off）返回 null
          final eff = effectiveDay(tt, w, di);
          if (eff == null) continue;
          for (final c in courses) {
            if (c.name.trim().isEmpty || c.day != eff || !meetsIn(c, w)) continue;
            final day = dateOfWeekWeek(start, w, di);
            final at = day
                .add(Duration(minutes: classStartMinutes(c)))
                .subtract(Duration(minutes: leadMinutes));
            if (at.isBefore(from) || !at.isBefore(until)) continue;
            final key = '${c.name}|${c.place}|${at.toIso8601String()}';
            if (!seen.add(key)) continue;
            out.add(ClassReminder(id: notificationIdFor(c, at), course: c, at: at));
          }
        }
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out.length > maxScheduled ? out.sublist(0, maxScheduled) : out;
  }

  /// 第 [week] 周第 [dayIndex] 列（0=周一）实际按星期几的课表上课；
  /// 该列被调休设为放假时返回 null。与课表页 _colEffDay 同规则，两边必须一致。
  static int? effectiveDay(SemesterTt tt, int week, int dayIndex) {
    if (tt.startDate.isEmpty) return dayIndex;
    final iso = TimetableStore.iso(TimetableStore.dateOfWeekDay(tt.startDate, week, dayIndex));
    for (final a in tt.adjustments) {
      if (a.date != iso) continue;
      return a.type == 'off' ? null : a.day;
    }
    return dayIndex;
  }

  static int notificationIdFor(TtCourse c, DateTime at) {
    var h = 17;
    for (final unit in '${c.name}|${c.day}|${c.slotStart}|${at.toIso8601String()}'.codeUnits) {
      h = (h * 31 + unit) & 0x3fffffff;
    }
    return h;
  }

  // ==================== 初始化 / 排期 ====================

  /// 初始化插件（幂等）。失败只记日志，不让提醒功能影响启动。
  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(_localLocation());
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
          ));
      _ready = true;
    } catch (e) {
      debugPrint('[上课提醒] 通知插件初始化失败：$e');
    }
  }

  /// 本机时区：优先用设备时区名，取不到就按当前 UTC 偏移量匹配等价时区
  /// （中国是固定 +08:00，无夏令时，偏移量足够准确）。
  static tz.Location _localLocation() {
    final name = DateTime.now().timeZoneName;
    for (final candidate in [name, if (name == 'CST') 'Asia/Shanghai']) {
      try {
        return tz.getLocation(candidate);
      } catch (_) {}
    }
    final offset = DateTime.now().timeZoneOffset;
    for (final l in tz.timeZoneDatabase.locations.values) {
      if (l.currentTimeZone.offset == offset.inMilliseconds) return l;
    }
    debugPrint('[上课提醒] 设备时区 "$name" 不可识别，按 UTC 处理（提醒时刻可能偏移）');    return tz.getLocation('UTC');
  }

  /// 重新排期：清空本 App 排过的通知，再按当前课表排未来 [horizonDays] 天的提醒。
  ///
  /// 做之前先问 [actionFor] 该做什么——**课表还没读出来的时候不能清空**：
  /// 启动早期提醒服务会先于课表加载跑一遍，那时 plan() 是空的，
  /// 「先清空再排 0 条」会把用户上一次排好的提醒全删掉，而之后只有「保存课表」
  /// 才会重排，于是不刷新课表的那次启动之后，提醒就再也不来了。
  Future<void> reschedule() async {
    await init();
    if (!_ready) return;
    try {
      final reminders = plan(TimetableStore.instance, DateTime.now());
      final action = actionFor(
        enabled: _enabled,
        pluginEnabled: PluginRegistry.I.isEnabled(reminderPluginId),
        storeHasSemesters: TimetableStore.instance.semesters.isNotEmpty,
        planned: reminders.length,
      );
      if (action == ReminderAction.skip) {
        debugPrint('[上课提醒] 课表尚未读出来，保留现有排期不动');
        return;
      }
      await _plugin.cancelAll();
      if (action == ReminderAction.clearOnly) return;
      // 精确闹钟（AlarmManager.setExactAndAllowWhileIdle）在未授权的机型上会直接抛异常，
      // 结果是**一条都排不上**（原来只打日志，用户那边就是「提醒根本不弹」）。
      // 这里先探一次权限：不允许就降级成不精确闹钟——差几分钟，但提醒能到。
      final mode = await _scheduleMode();
      for (final r in reminders) {
        await _plugin.zonedSchedule(
          r.id,
          '${r.course.name} 即将上课',
          _body(r, leadMinutes),
          tz.TZDateTime.from(r.at, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDesc,
              importance: Importance.high,
              priority: Priority.high,
              category: AndroidNotificationCategory.reminder,
            ),
          ),
          androidScheduleMode: mode,
        );
      }
      debugPrint('[上课提醒] 已排期 ${reminders.length} 条（未来 $horizonDays 天，'
          '${mode == AndroidScheduleMode.exactAllowWhileIdle ? '精确' : '不精确'}闹钟）');
    } catch (e) {
      // 排期异常不让提醒功能炸掉页面
      debugPrint('[上课提醒] 排期失败：$e');
    }
  }

  /// 这次 [reschedule] 该做什么——纯函数，rule 越直白越好测。
  @visibleForTesting
  static ReminderAction actionFor({
    required bool enabled,
    required bool pluginEnabled,
    required bool storeHasSemesters,
    required int planned,
  }) {
    // 关掉开关、或插件被停用/从清单删掉 → 只清空
    if (!enabled || !pluginEnabled) return ReminderAction.clearOnly;
    // 课表还没读出来（store 里一个学期都没有）：这时清空等于把用户已排好的提醒删光，
    // 而且当场排不出新的。宁可什么都不做——store.load() 完会再调一次。
    if (!storeHasSemesters && planned == 0) return ReminderAction.skip;
    return ReminderAction.reschedule;
  }

  /// 能否用精确闹钟；取不到（非 Android / 插件不支持）时按不能处理，宁可不精确也别排不上。
  Future<AndroidScheduleMode> _scheduleMode() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final ok = await android?.canScheduleExactNotifications();
      if (ok == true) return AndroidScheduleMode.exactAllowWhileIdle;
    } catch (e) {
      debugPrint('[上课提醒] 精确闹钟权限探活失败，改用不精确闹钟：$e');
    }
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  static String _body(ClassReminder r, int lead) =>
      '${_hhmm(classStartMinutes(r.course))} 上课'
      '${r.course.place.isEmpty ? '' : ' · ${r.course.place}'}'
      '（$lead 分钟后）';

  static String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  // ==================== 权限 + 开关 ====================

  /// 打开提醒：Android 13+ 需要通知权限，精确闹钟在部分机型需要用户授权。
  /// 返回 null 表示成功，否则返回要展示给用户的提示。
  Future<String?> enable() async {
    await init();
    if (!_ready) return '通知功能初始化失败，请重启 App 后重试';
    AndroidFlutterLocalNotificationsPlugin? android;
    try {
      android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    } catch (_) {}
    try {
      final granted = await android?.requestNotificationsPermission();
      if (granted == false) {
        return '未获得通知权限：请在系统设置里允许 AntiSIT 发送通知';
      }
      final canExact = await android?.canScheduleExactNotifications();
      if (canExact == false) {
        await android?.requestExactAlarmsPermission();
        final after = await android?.canScheduleExactNotifications();
        if (after == false) {
          await _setEnabled(true);
          await reschedule();
          return '已开启，但系统未允许「精确闹钟」：提醒可能延迟几分钟。'
              '可在系统设置 → 应用 → AntiSIT → 闹钟与提醒里允许';
        }
      }
    } catch (e) {
      debugPrint('[上课提醒] 权限申请异常：$e');
    }
    await _setEnabled(true);
    await reschedule();
    return null;
  }

  /// 关闭提醒：清掉已排期的通知。
  Future<void> disable() async {
    await _setEnabled(false);
    await reschedule();
  }

  // ==================== 自检 + 引导 ====================

  /// 跳设置页用的通道（原生侧见 android/.../MainActivity.kt）。非 Android 恒为 null。
  static const _systemChannel = MethodChannel('antisit/system');

  /// 提醒自检：真要能弹出来，除了排期还依赖通知权限、精确闹钟、后台不被省电策略掐死。
  /// 探测失败（非 Android / 模拟器缺页面）一律返回 null，界面上就不显示这一项。
  ///
  /// 这里**不初始化通知插件**：查权限只走平台实现，初始化与否都能查；
  /// 而 `initialize()` 在测试环境（没有平台通道）会挂住，这类自检没必要绑上它。
  Future<ReminderHealth> health() async {
    AndroidFlutterLocalNotificationsPlugin? android;
    try {
      // 测试 / 桌面端没有注册平台实现，这个 getter 自己会抛，所以它也得在 try 里
      android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    } catch (_) {}
    bool? notifications;
    bool? exact;
    bool? battery;
    try {
      notifications = await android?.areNotificationsEnabled();
    } catch (_) {}
    try {
      exact = await android?.canScheduleExactNotifications();
    } catch (_) {}
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        battery = await _systemChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      }
    } catch (_) {}
    return ReminderHealth(
      notifications: notifications,
      exactAlarm: exact,
      batteryUnrestricted: battery,
      planned: plan(TimetableStore.instance, DateTime.now()).length,
    );
  }

  /// 去系统里允许「精确闹钟」（Android 12+；部分机型必须用户手动开）。
  Future<void> openExactAlarmSettings() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint('[上课提醒] 打开精确闹钟设置失败：$e');
    }
  }

  /// 去系统里把通知打开（被拒过之后只能从设置页开）。返回 false = 这个 ROM 没有对应页面。
  Future<bool> openNotificationSettings() => _openSystem('openNotificationSettings');

  /// 去「电池优化」列表页，把本 App 设为不优化。
  Future<bool> openBatterySettings() => _openSystem('openBatteryOptimizationSettings');

  /// 去应用信息页（各家 ROM 的省电策略 / 自启动开关都在这里）。
  Future<bool> openAppInfoSettings() => _openSystem('openAppInfoSettings');

  Future<bool> _openSystem(String method) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _systemChannel.invokeMethod<bool>(method) ?? false;
    } catch (e) {
      debugPrint('[上课提醒] 打开系统设置页失败（$method）：$e');
      return false;
    }
  }
}

/// [ClassReminderService.reschedule] 的三种打算。
enum ReminderAction {
  /// 什么都不做：还不能判断（课表还没读出来），别把已有排期清掉。
  skip,

  /// 只清空：提醒被关掉，或「上课提醒」插件被停用 / 从清单删掉。
  clearOnly,

  /// 清空后按当前课表重排。
  reschedule,
}

/// 上课提醒的「能不能真的弹出来」自检结果。
/// 每项 null = 该平台没有这个概念 / 这次没探测出来。
@immutable
class ReminderHealth {
  const ReminderHealth({
    this.notifications,
    this.exactAlarm,
    this.batteryUnrestricted,
    this.planned = 0,
  });

  /// 通知权限（Android 13+ 需用户授权）。
  final bool? notifications;

  /// 能否用精确闹钟（Android 12+；不允许就只能用不精确闹钟，可能晚几分钟）。
  final bool? exactAlarm;

  /// 是否已被排除在电池优化之外（false = 省电策略可能在后台掐掉提醒）。
  final bool? batteryUnrestricted;

  /// 按当前课表，未来 [ClassReminderService.horizonDays] 天会排多少条提醒。
  final int planned;

  /// 三项都没问题。
  bool get allGood =>
      notifications != false && exactAlarm != false && batteryUnrestricted != false;

  /// 需要用户去系统里处理的项数（探测不到的项不算，那不是问题）。
  int get issueCount => [
        notifications == false,
        exactAlarm == false,
        batteryUnrestricted == false,
      ].where((bad) => bad).length;

  /// 摘要用的第一处问题；都正常返回 null。
  String? get firstIssue {
    if (notifications == false) return '通知权限未允许';
    if (exactAlarm == false) return '精确闹钟未允许';
    if (batteryUnrestricted == false) return '后台运行受限制';
    return null;
  }
}
