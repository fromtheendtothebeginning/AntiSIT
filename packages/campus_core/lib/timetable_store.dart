import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'app_state.dart';
import 'json_num.dart';
import 'plugins/course_cloud_capability.dart';
import 'plugins/home_widget_capability.dart';
import 'plugins/plugin.dart';
import 'plugins/registry.dart';
import 'plugins/reminder_capability.dart';
import 'timetable_models.dart';
import 'timetable_schedule.dart';

// 课表模型随本文件一并暴露，外部仍可用 `campus_core.dart` 里的 TtCourse 等类型。
export 'timetable_models.dart';

/// 本地课表存储：多学期课表 + 作息表 + 与网站的云端互通（updatedAt 最后写入胜）。
class TimetableStore {
  TimetableStore._();
  static final TimetableStore instance = TimetableStore._();

  static const _spKey = 'campus_timetable';

  /// 自定义上课时间的存储键：云端不认这个字段，换设备不覆盖本机作息。
  static const _slotTimesKey = 'campus_slot_times';

  /// 默认的 11 节上课 / 下课时刻（索引 = 节次序号，0 起）。
  static const List<String> defaultSlotStarts = [
    '08:20', '09:10', '10:15', '11:05', '13:00', '13:50', '14:55', '15:45', '18:00', '18:50', '19:40',
  ];
  static const List<String> defaultSlotEnds = [
    '09:05', '09:55', '11:00', '11:50', '13:45', '14:35', '15:40', '16:30', '18:45', '19:35', '20:25',
  ];

  /// 当前生效的 11 节时刻：课表页、导出日历、上课提醒共用这一份表。
  static List<String> slotStarts = defaultSlotStarts;
  static List<String> slotEnds = defaultSlotEnds;

  /// 用户改过作息没有（设置页据此显示「自定义 / 默认」）。
  static bool get slotTimesCustomized =>
      !listEquals(slotStarts, defaultSlotStarts) || !listEquals(slotEnds, defaultSlotEnds);

  /// 保存自定义的 11 节上课 / 下课时刻（`HH:mm`）；不传 = 恢复默认。
  static Future<void> setSlotTimes({List<String>? starts, List<String>? ends}) async {
    final sp = await SharedPreferences.getInstance();
    if (starts == null || ends == null) {
      slotStarts = defaultSlotStarts;
      slotEnds = defaultSlotEnds;
      await sp.remove(_slotTimesKey);
    } else {
      slotStarts = List.unmodifiable(starts);
      slotEnds = List.unmodifiable(ends);
      await sp.setString(_slotTimesKey, jsonEncode({'starts': starts, 'ends': ends}));
    }
    _rescheduleReminder();
  }

  /// 读自定义时刻：缺省 / 坏数据 / 长度不是 11 节，一律回默认。
  static void _loadSlotTimes(SharedPreferences sp) {
    final raw = sp.getString(_slotTimesKey);
    if (raw == null) {
      slotStarts = defaultSlotStarts;
      slotEnds = defaultSlotEnds;
      return;
    }
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final starts = [for (final v in (m['starts'] as List)) '$v'];
      final ends = [for (final v in (m['ends'] as List)) '$v'];
      if (starts.length == defaultSlotStarts.length && ends.length == defaultSlotEnds.length) {
        slotStarts = List.unmodifiable(starts);
        slotEnds = List.unmodifiable(ends);
        return;
      }
    } catch (e) {
      debugPrint('[课表] 自定义上课时间读取失败，用默认：$e');
    }
    slotStarts = defaultSlotStarts;
    slotEnds = defaultSlotEnds;
  }

  /// 学期 key：`学年-学期码`（正方：3=第一学期 / 12=第二学期 / 16=短学期）
  Map<String, SemesterTt> semesters = {};
  String active = '';
  int updatedAt = 0;
  String? _nj;

  /// 是否已经从本机读过一次课表（load 前不可信，插件别拿空课表去清原生排期）。
  bool loaded = false;

  /// 学期显示名：基于入学年换算「大一上~大四下」。
  String? semesterLabel(String key) {
    final nj = int.tryParse(_nj ?? '');
    if (nj == null || _nj!.length != 4) return null;
    final parts = key.split('-');
    if (parts.length != 2) return null;
    final xnm = int.tryParse(parts[0]);
    final xqm = parts[1];
    if (xnm == null) return null;
    final term = (xnm - nj) * 2 + (xqm == '12' ? 2 : 1);
    const names = ['大一上', '大一下', '大二上', '大二下', '大三上', '大三下', '大四上', '大四下'];
    if (term < 1 || term > 8) return null;
    return names[term - 1];
  }

  String keyOf(String xnm, String xqm) => '$xnm-$xqm';

  SemesterTt semester(String xnm, String xqm) {
    final k = keyOf(xnm, xqm);
    return semesters.putIfAbsent(k, () => SemesterTt());
  }

  /// 导入备份前清空内存里的课表，避免备份未包含课表时旧数据残留。
  void resetForImport() {
    semesters = {};
    active = '';
    updatedAt = 0;
    _nj = null;
    loaded = false;
  }

  /// 从本机读课表（首次运行时顺带迁移旧版周缓存），完成后重排提醒。
  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _loadSlotTimes(sp);
    final raw = sp.getString(_spKey);
    if (raw != null) {
      _adoptJson(jsonDecode(raw));
    } else {
      await _migrateLegacyCache(sp);
    }
    // 启动早期提醒服务会先跑一遍（那时 store 还是空的，会主动跳过），这里补一发。
    loaded = true;
    _rescheduleReminder();
    debugPrint('[课表] 载入完成 → 重排上课提醒');
  }

  void _adoptJson(dynamic decoded) {
    try {
      final m = decoded as Map<String, dynamic>;
      _nj = m['nj'] as String?;
      active = '${m['active'] ?? ''}';
      updatedAt = asInt(m['updatedAt']) ?? 0;
      final sems = (m['semesters'] as Map<String, dynamic>?) ?? {};
      semesters =
          sems.map((k, v) => MapEntry(k, SemesterTt.fromJson(v as Map<String, dynamic>)));
    } catch (_) {}
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'nj': _nj,
        'active': active.isNotEmpty ? active : (semesters.keys.isNotEmpty ? semesters.keys.first : ''),
        'semesters': semesters.map((k, v) => MapEntry(k, v.toJson())),
        'updatedAt': updatedAt,
      };

  /// 旧版按学期的周缓存（`tt_cache_<xnm>_<xqm>`）迁入本地 store 的教务原始数据。
  Future<void> _migrateLegacyCache(SharedPreferences sp) async {
    final keys = sp.getKeys().where((k) => k.startsWith('tt_cache_')).toList();
    if (keys.isEmpty) return;
    for (final key in keys) {
      try {
        final parts = key.substring('tt_cache_'.length).split('_');
        if (parts.length != 2) continue;
        final m = jsonDecode(sp.getString(key)!) as Map<String, dynamic>;
        final tt = semesters.putIfAbsent('${parts[0]}-${parts[1]}', () => SemesterTt());
        if ((tt.startDate).isEmpty) tt.startDate = '${m['start'] ?? ''}';
        final weeks = (m['weeks'] as Map<String, dynamic>?) ?? {};
        for (final e in weeks.entries) {
          if ((e.value as Map<String, dynamic>)['empty'] == true) continue;
          final resp = e.value['resp'] as Map<String, dynamic>?;
          if (resp == null) continue;
          tt.jwxtWeeks[e.key] = ((resp['courses'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(TtCourse.fromJson)
              .toList();
        }
      } catch (_) {}
      await sp.remove(key);
    }
    await persist();
  }

  /// 本地写入（[touch] 为 false 时保留原 updatedAt，用于采纳云端数据）。
  Future<void> persist({bool touch = true}) async {
    if (touch) updatedAt = DateTime.now().millisecondsSinceEpoch;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_spKey, jsonEncode(toJson()));
    // 课表变了，上课提醒随之重排（排期是幂等覆盖，未开启时不做事）
    _rescheduleReminder();
  }

  /// 按 id 取提醒 / 课程通知 / 桌面卡片能力，插件没装或停用时取不到就跳过。
  static void _rescheduleReminder() {
    final reminder = PluginRegistry.I.capability<ReminderCapability>(PluginIds.reminder);
    if (reminder != null) unawaited(reminder.reschedule());
    final courseCloud = PluginRegistry.I.capability<CourseCloudCapability>(PluginIds.courseCloud);
    if (courseCloud != null) unawaited(courseCloud.sync());
    final widget = PluginRegistry.I.capability<HomeWidgetCapability>(PluginIds.homeWidget);
    if (widget != null) unawaited(_syncHomeWidget(widget));
  }

  /// 今天的课同步给桌面卡片（启动、课表保存各来一次，幂等）。
  static Future<void> _syncHomeWidget(HomeWidgetCapability widget) async {
    try {
      final now = DateTime.now();
      final courses = todayCourses(now: now);
      final nowHHmm = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}';
      final upcoming = [for (final c in courses) if (c.end.compareTo(nowHHmm) > 0) c];
      await widget.syncTimetable(
        day: ttIso(now),
        date: '${now.month}月${now.day}日 周${'一二三四五六日'[now.weekday - 1]}',
        courses: courses,
        next: upcoming.isEmpty ? null : upcoming.first,
      );
    } catch (e) {
      debugPrint('[课表] 同步桌面卡片失败：$e');
    }
  }

  /// 今天的课（桌面课表卡片用）：调休换算后的星期、单双周、节次起止都按当前作息算。
  static List<HomeWidgetCourse> todayCourses({DateTime? now}) {
    final t = now ?? DateTime.now();
    final dayIndex = t.weekday - 1;
    final starts = slotStarts;
    final ends = slotEnds;
    if (starts.isEmpty || ends.isEmpty) return const [];
    final todayIso = ttIso(DateTime(t.year, t.month, t.day));
    final out = <HomeWidgetCourse>[];
    for (final tt in instance.semesters.values) {
      final week = ttWeekOf(tt.startDate, tt.weekCount, t);
      if (week == null) continue;
      var eff = dayIndex;
      for (final a in tt.adjustments) {
        if (a.date != todayIso) continue;
        eff = a.type == 'off' ? -1 : a.day;
      }
      if (eff < 0) continue;
      final courses = ttDeriveImported(tt).followedBy(tt.courses);
      for (final c in courses) {
        if (c.name.trim().isEmpty || c.day != eff) continue;
        if (week < c.weekStart || week > c.weekEnd) continue;
        if (c.weekType == 'odd' && week.isEven) continue;
        if (c.weekType == 'even' && week.isOdd) continue;
        final s = c.slotStart.clamp(0, starts.length - 1);
        final e = c.slotEnd.clamp(s, ends.length - 1);
        out.add(HomeWidgetCourse(
          name: c.name.trim(),
          place: c.place.trim(),
          start: starts[s],
          end: ends[e],
        ));
      }
    }
    final seen = <String>{};
    return [
      for (final c in out)
        if (seen.add('${c.name}|${c.start}|${c.place}')) c,
    ]..sort((a, b) => a.start.compareTo(b.start));
  }

  /// 本地写入 + 登录状态下回推云端（网站同款 PUT /api/timetable {data}）。
  Future<void> save() async {
    await persist();
    _pushCloud();
  }

  void _pushCloud() {
    if (!AppState.I.loggedIn || AppState.I.demo || AppState.I.direct) return;
    final data = toJson();
    ApiClient.I.timetableCloudPut(data).catchError((_) {});
  }

  /// 登录后拉云端合并：云端较新则整体采纳（返回 true），本地较新则回推。
  /// 直连模式没有云端课表（数据源是学校教务 + 本机存储）。
  Future<bool> syncCloud() async {
    if (!AppState.I.loggedIn || AppState.I.demo || AppState.I.direct) return false;
    try {
      final r = await ApiClient.I.timetableCloudGet();
      final data = r['data'];
      if (data is! Map<String, dynamic>) {
        _pushCloud(); // 云端还没有数据：把本地推上去
        return false;
      }
      final cloudAt = asInt(data['updatedAt']) ?? 0;
      if (cloudAt > updatedAt) {
        semesters = {};
        _adoptJson(data);
        await persist(touch: false);
        return true;
      }
      if (updatedAt > cloudAt) _pushCloud();
    } catch (_) {}
    return false;
  }

  /// 教务导入成功响应里的年级（用于学期命名）。
  String? get nj => _nj;
  set nj(String? v) {
    _nj = v;
    persist();
  }

  // ── 学期换算 / 课程推导：实现见 timetable_schedule.dart ──

  static String semesterKeyOf(DateTime? start) => ttSemesterKeyOf(start);

  static int? locateToday(String? startDate, int weekCount) =>
      ttLocateToday(startDate, weekCount);

  static int todayDayIndex() => ttTodayDayIndex();

  static bool lessonPassed(String colISO, String endHHmm, {DateTime? now}) =>
      ttLessonPassed(colISO, endHHmm, now: now);

  static List<TtCourse> upcomingOn(
    List<TtCourse> courses, {
    required String startDate,
    required int week,
    required int dayIndex,
    required List<String> endTimes,
    DateTime? now,
  }) =>
      ttUpcomingOn(courses,
          startDate: startDate, week: week, dayIndex: dayIndex, endTimes: endTimes, now: now);

  static List<TtCourse> pastOn(
    List<TtCourse> courses, {
    required String startDate,
    required int week,
    required int dayIndex,
    required List<String> endTimes,
    DateTime? now,
  }) =>
      ttPastOn(courses,
          startDate: startDate, week: week, dayIndex: dayIndex, endTimes: endTimes, now: now);

  static DateTime dateOfWeekDay(String startDate, int week, int dayIndex) =>
      ttDateOfWeekDay(startDate, week, dayIndex);

  static String iso(DateTime d) => ttIso(d);

  static bool coversWeek(TtCourse c, int zs) => ttCoversWeek(c, zs);

  static List<TtCourse> deriveImported(SemesterTt tt) => ttDeriveImported(tt);

  static void removeImportedSegment(SemesterTt tt, TtCourse c) =>
      ttRemoveImportedSegment(tt, c);

  static void removeImportedOccurrence(SemesterTt tt, TtCourse item,
          {required bool all, int week = 0}) =>
      ttRemoveImportedOccurrence(tt, item, all: all, week: week);

  static List<TtAdjust> mergeAdjustments(List<TtAdjust> prev, List<TtAdjust> entries) =>
      ttMergeAdjustments(prev, entries);

  static List<DateTime> expandDateRange(String start, String? end) =>
      ttExpandDateRange(start, end);

  static int addExamEvents(SemesterTt tt, List<Map<String, dynamic>> exams) =>
      ttAddExamEvents(tt, exams);

  static String genId() => ttGenId();
}
