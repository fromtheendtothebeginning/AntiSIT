import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../timetable_store.dart';

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
      if (tt.startDate.isEmpty || tt.weekCount <= 0) continue;
      for (final c in TimetableStore.deriveImported(tt) + tt.courses) {
        if (c.name.trim().isEmpty) continue;
        for (var w = 1; w <= tt.weekCount; w++) {
          if (!meetsIn(c, w)) continue;
          final start = classStart(tt.startDate, w, c);
          if (start == null) continue;
          final at = start.subtract(Duration(minutes: leadMinutes));
          if (at.isBefore(from) || !at.isBefore(until)) continue;
          final key = '${c.name}|${c.place}|${at.toIso8601String()}';
          if (!seen.add(key)) continue;
          out.add(ClassReminder(id: notificationIdFor(c, at), course: c, at: at));
        }
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out.length > maxScheduled ? out.sublist(0, maxScheduled) : out;
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

  /// 重新排期：先清空本 App 排过的通知，再按当前课表排未来 [horizonDays] 天的提醒。
  /// 关掉开关时只清空、不排期。
  Future<void> reschedule() async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      if (!_enabled) return;
      final reminders = plan(TimetableStore.instance, DateTime.now());
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
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }
      debugPrint('[上课提醒] 已排期 ${reminders.length} 条（未来 $horizonDays 天）');
    } catch (e) {
      // 精确闹钟权限被撤销等情况：不让提醒功能炸掉页面
      debugPrint('[上课提醒] 排期失败：$e');
    }
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
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
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
}
