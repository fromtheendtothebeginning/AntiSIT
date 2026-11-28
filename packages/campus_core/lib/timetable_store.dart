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

  /// 上一份可用的课表快照（云端整体覆盖前留的底）。主键读不出来时（写盘中断 /
  /// 脏数据）用它兜底，避免一次坏数据就让课表变空、进而被回推云端。
  static const _spBackupKey = 'campus_timetable_backup';

  /// 自定义上课时间的存储键：云端不认这个字段，换设备不覆盖本机作息。
  static const _slotTimesKey = 'campus_slot_times';

  /// 默认的 11 节上课 / 下课时刻（索引 = 节次序号，0 起）。
  static const List<String> defaultSlotStarts = [
    '08:20',
    '09:10',
    '10:15',
    '11:05',
    '13:00',
    '13:50',
    '14:55',
    '15:45',
    '18:00',
    '18:50',
    '19:40',
  ];
  static const List<String> defaultSlotEnds = [
    '09:05',
    '09:55',
    '11:00',
    '11:50',
    '13:45',
    '14:35',
    '15:40',
    '16:30',
    '18:45',
    '19:35',
    '20:25',
  ];

  /// 当前生效的 11 节时刻：课表页、导出日历、上课提醒共用这一份表。
  static List<String> slotStarts = defaultSlotStarts;
  static List<String> slotEnds = defaultSlotEnds;

  /// 用户改过作息没有（设置页据此显示「自定义 / 默认」）。
  static bool get slotTimesCustomized =>
      !listEquals(slotStarts, defaultSlotStarts) ||
      !listEquals(slotEnds, defaultSlotEnds);

  /// 保存自定义的 11 节上课 / 下课时刻（`HH:mm`）；不传 = 恢复默认。
  static Future<void> setSlotTimes({
    List<String>? starts,
    List<String>? ends,
  }) async {
    final sp = await SharedPreferences.getInstance();
    if (starts == null || ends == null) {
      slotStarts = defaultSlotStarts;
      slotEnds = defaultSlotEnds;
      await sp.remove(_slotTimesKey);
    } else {
      slotStarts = List.unmodifiable(starts);
      slotEnds = List.unmodifiable(ends);
      await sp.setString(
        _slotTimesKey,
        jsonEncode({'starts': starts, 'ends': ends}),
      );
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
      if (starts.length == defaultSlotStarts.length &&
          ends.length == defaultSlotEnds.length) {
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
  ///
  /// 本机数据坏了（写盘中断 / 旧版本格式变更）不能让启动卡死：主键解析失败就退回
  /// 上一次的快照，快照也没有才当空课表——**绝不把空课表当成真实数据写回**。
  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _loadSlotTimes(sp);
    final raw = sp.getString(_spKey);
    var ok = false;
    var repaired = false;
    if (raw != null) {
      ok = _tryAdoptJson(raw, source: '本机');
      if (!ok) {
        final backup = sp.getString(_spBackupKey);
        if (backup != null) {
          ok = _tryAdoptJson(backup, source: '本机快照');
          repaired = ok;
        }
      }
    } else {
      await _migrateLegacyCache(sp);
    }
    // 用快照救回来以后立刻把主键写回正常内容，免得每次冷启动都走一遍回退。
    if (repaired) {
      await sp.setString(_spKey, jsonEncode(toJson()));
      debugPrint('[课表] 本机课表已损坏，已用上一次的快照恢复');
    }
    // 启动早期提醒服务会先跑一遍（那时 store 还是空的，会主动跳过），这里补一发。
    loaded = true;
    _rescheduleReminder();
    debugPrint(
      '[课表] 载入完成 → 重排上课提醒${ok || raw == null ? '' : '（本机数据已损坏，本次为空课表）'}',
    );
  }

  /// 把落盘的 JSON 字符串采纳进内存；解析或结构不对时返回 false，不动现有内存状态。
  bool _tryAdoptJson(String raw, {String source = ''}) {
    try {
      return _adoptJson(jsonDecode(raw));
    } catch (e) {
      debugPrint('[课表] $source课表解析失败，已忽略：$e');
      return false;
    }
  }

  /// 采纳课表 JSON：**先在临时变量里完整解析，全部成功才赋值**。
  ///
  /// 返回 false = 数据结构不符（被调用方当作「没读到」处理）。旧实现边解析边写字段、
  /// 异常被吞掉，云端一份脏数据就能把本地课表换成空表并落盘，属于会丢数据的行为。
  bool _adoptJson(dynamic decoded) {
    try {
      final m = decoded as Map<String, dynamic>;
      final nj = m['nj'] as String?;
      final active = '${m['active'] ?? ''}';
      final updatedAt = _saneUpdatedAt(asInt(m['updatedAt']) ?? 0);
      final sems = (m['semesters'] as Map<String, dynamic>?) ?? {};
      final parsed = sems.map(
        (k, v) => MapEntry(k, SemesterTt.fromJson(v as Map<String, dynamic>)),
      );
      _nj = nj;
      this.active = active;
      this.updatedAt = updatedAt;
      semesters = parsed;
      return true;
    } catch (e) {
      debugPrint('[课表] 课表数据格式不符，已忽略：$e');
      return false;
    }
  }

  /// 时钟明显不对时的时间戳（设备时间被调到未来再调回来，或数据损坏）会把同步锁死：
  /// 本机时间戳永远「更新」，别的设备怎么改都推不进来。超出当前时间 1 天的按 0 处理。
  static int _saneUpdatedAt(int v) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (v > now + const Duration(days: 1).inMilliseconds) {
      debugPrint('[课表] 云端/本机 updatedAt 明显超前（$v），按 0 处理以免同步被锁死');
      return 0;
    }
    return v;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'nj': _nj,
    'active': active.isNotEmpty
        ? active
        : (semesters.keys.isNotEmpty ? semesters.keys.first : ''),
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
        final tt = semesters.putIfAbsent(
          '${parts[0]}-${parts[1]}',
          () => SemesterTt(),
        );
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
    final json = jsonEncode(toJson());
    // 覆盖前把上一版**可解析**的内容留成快照：主键写坏时 load 还能退回上一次的课表。
    final prev = sp.getString(_spKey);
    if (prev != null && prev != json) {
      try {
        jsonDecode(prev);
        await sp.setString(_spBackupKey, prev);
      } catch (_) {}
    }
    await sp.setString(_spKey, json);
    // 课表变了，上课提醒随之重排（排期是幂等覆盖，未开启时不做事）
    _rescheduleReminder();
  }

  /// 按 id 取提醒 / 课程通知 / 桌面卡片能力，插件没装或停用时取不到就跳过。
  static void _rescheduleReminder() {
    final reminder = PluginRegistry.I.capability<ReminderCapability>(
      PluginIds.reminder,
    );
    if (reminder != null) unawaited(reminder.reschedule());
    final courseCloud = PluginRegistry.I.capability<CourseCloudCapability>(
      PluginIds.courseCloud,
    );
    if (courseCloud != null) unawaited(courseCloud.sync());
    final widget = PluginRegistry.I.capability<HomeWidgetCapability>(
      PluginIds.homeWidget,
    );
    if (widget != null) unawaited(_syncHomeWidget(widget));
  }

  /// 今天的课同步给桌面卡片（启动、课表保存各来一次，幂等）。
  static Future<void> _syncHomeWidget(HomeWidgetCapability widget) async {
    try {
      final now = DateTime.now();
      final courses = todayCourses(now: now);
      final nowHHmm =
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}';
      final upcoming = [
        for (final c in courses)
          if (c.end.compareTo(nowHHmm) > 0) c,
      ];
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
        out.add(
          HomeWidgetCourse(
            name: c.name.trim(),
            place: c.place.trim(),
            start: starts[s],
            end: ends[e],
          ),
        );
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

  /// 云端回推串行队列：连续两次 save 会发两次 PUT，若不排队，先发的可能后到，
  /// 服务端按「后到者胜」存下来就会把新数据覆盖成旧数据。
  Future<void> _pushQueue = Future.value();

  void _pushCloud() {
    if (!AppState.I.loggedIn || AppState.I.demo || AppState.I.direct) return;
    final data = toJson();
    _pushQueue = _pushQueue.then((_) async {
      try {
        await ApiClient.I.timetableCloudPut(data);
      } catch (_) {
        // 回推失败不影响本地：下次 save / 下次登录会再推一次
      }
    });
  }

  /// 登录后拉云端合并：云端较新则整体采纳（返回 true），本地较新则回推。
  /// 直连模式没有云端课表（数据源是学校教务 + 本机存储）。
  ///
  /// 云端的 `data` 必须先完整解析成功才动手：解析失败当作「这次没同步」，
  /// 既不清内存也不落盘——旧实现先 `semesters = {}` 再吞掉解析异常，
  /// 一份脏数据就会把本地课表换成空表写盘，还会在下次回推时污染云端。
  Future<bool> syncCloud() async {
    if (!AppState.I.loggedIn || AppState.I.demo || AppState.I.direct) {
      return false;
    }
    try {
      final r = await ApiClient.I.timetableCloudGet();
      final data = r['data'];
      if (data is! Map<String, dynamic>) {
        _pushCloud(); // 云端还没有数据：把本地推上去
        return false;
      }
      final cloudAt = _saneUpdatedAt(asInt(data['updatedAt']) ?? 0);
      if (cloudAt > updatedAt) {
        if (!_adoptJson(data)) return false; // 云端结构不对：保持本地原样
        await persist(touch: false);
        return true;
      }
      if (updatedAt > cloudAt) {
        _pushCloud();
      } else if (updatedAt == cloudAt && semesters.isNotEmpty) {
        // 时间戳相同不代表内容相同（两台设备同一毫秒各存一次）：内容有差异时
        // 以本机为准回推一次，否则两边会永远各持己见、谁也发现不了分叉。
        if (_canonicalJson(toJson()) != _canonicalJson(data)) {
          debugPrint('[课表] 云端与本机 updatedAt 相同但内容不同，以本机为准回推');
          _pushCloud();
        }
      }
    } catch (_) {}
    return false;
  }

  /// 规范化 JSON（对象键递归排序）：只比较内容，不受键顺序 / 数字写法影响。
  static String _canonicalJson(dynamic v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return '{${keys.map((k) => '${jsonEncode(k)}:${_canonicalJson(v[k])}').join(',')}}';
    }
    if (v is List) return '[${v.map(_canonicalJson).join(',')}]';
    return jsonEncode(v);
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
  }) => ttUpcomingOn(
    courses,
    startDate: startDate,
    week: week,
    dayIndex: dayIndex,
    endTimes: endTimes,
    now: now,
  );

  static List<TtCourse> pastOn(
    List<TtCourse> courses, {
    required String startDate,
    required int week,
    required int dayIndex,
    required List<String> endTimes,
    DateTime? now,
  }) => ttPastOn(
    courses,
    startDate: startDate,
    week: week,
    dayIndex: dayIndex,
    endTimes: endTimes,
    now: now,
  );

  static DateTime dateOfWeekDay(String startDate, int week, int dayIndex) =>
      ttDateOfWeekDay(startDate, week, dayIndex);

  static String iso(DateTime d) => ttIso(d);

  static bool coversWeek(TtCourse c, int zs) => ttCoversWeek(c, zs);

  static List<TtCourse> deriveImported(SemesterTt tt) => ttDeriveImported(tt);

  static void removeImportedSegment(SemesterTt tt, TtCourse c) =>
      ttRemoveImportedSegment(tt, c);

  static void removeImportedOccurrence(
    SemesterTt tt,
    TtCourse item, {
    required bool all,
    int week = 0,
  }) => ttRemoveImportedOccurrence(tt, item, all: all, week: week);

  static List<TtAdjust> mergeAdjustments(
    List<TtAdjust> prev,
    List<TtAdjust> entries,
  ) => ttMergeAdjustments(prev, entries);

  static List<DateTime> expandDateRange(String start, String? end) =>
      ttExpandDateRange(start, end);

  static int addExamEvents(SemesterTt tt, List<Map<String, dynamic>> exams) =>
      ttAddExamEvents(tt, exams);

  static DateTime? semesterStartOf(SemesterTt tt) => ttSemesterStart(tt);

  static DateTime? semesterEndOf(SemesterTt tt) => ttSemesterEnd(tt);

  static bool eventOccursOn(SemesterTt tt, TtEvent e, DateTime date) =>
      ttEventOccursOn(tt, e, date);

  static bool eventOccursBetween(
    SemesterTt tt,
    TtEvent e,
    DateTime from,
    DateTime to,
  ) => ttEventOccursBetween(tt, e, from, to);

  static DateTime? eventNextOccurrence(
    SemesterTt tt,
    TtEvent e,
    DateTime from, {
    int limitDays = 400,
  }) => ttEventNextOccurrence(tt, e, from, limitDays: limitDays);

  static String genId() => ttGenId();
}
