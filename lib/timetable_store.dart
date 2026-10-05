import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'json_num.dart';
import 'app_state.dart';

/// 本地课表存储：对齐 anticraft.top 网站课程表的数据模型与算法
/// （多学期 store、手动课程、调休规则、教务原始周数据、考试日程）。
/// 数据存本机（SharedPreferences `campus_timetable`）；
/// 登录后经 GET/PUT /api/timetable 与网站云端互通（updatedAt 最后写入胜）。
class TimetableStore {
  TimetableStore._();
  static final TimetableStore instance = TimetableStore._();

  static const _spKey = 'campus_timetable';

  /// 学期 key：`学年-学期码`（正方：3=第一学期 / 12=第二学期 / 16=短学期）
  Map<String, SemesterTt> semesters = {};
  String active = '';
  int updatedAt = 0;
  String? _nj;

  /// 学期显示名：基于入学年 nj 换算「大一上~大四下」（与网站 semesterLabel 一致）。
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

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_spKey);
    if (raw != null) {
      _adoptJson(jsonDecode(raw));
      return;
    }
    await _migrateLegacyCache(sp);
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

  /// 教务导入成功响应里的年级（用于学期命名），与网站 store.nj 一致。
  String? get nj => _nj;
  set nj(String? v) {
    _nj = v;
    persist();
  }

  // ── 学期推算（与网站 semesterKeyOf / locateToday 一致）──

  static String semesterKeyOf(DateTime? start) {
    if (start == null) return 'default';
    final y = start.year;
    return switch (start.month) {
      >= 9 && <= 12 => '$y-3',
      1 => '${y - 1}-3',
      >= 2 && <= 6 => '${y - 1}-12',
      _ => '${y - 1}-16',
    };
  }

  /// 今天落在第几周（1 起），学期外或无起点返回 null。
  static int? locateToday(String? startDate, int weekCount) {
    final start = DateTime.tryParse(startDate ?? '');
    if (start == null || start.year <= 1970) return null;
    final s0 = DateTime(start.year, start.month, start.day);
    final now = DateTime.now();
    final n0 = DateTime(now.year, now.month, now.day);
    final totalDays = n0.difference(s0).inDays;
    final week = totalDays ~/ 7 + 1;
    if (week < 1 || week > weekCount) return null;
    return week;
  }

  static int todayDayIndex() => DateTime.now().weekday - 1; // 0=周一

  static DateTime dateOfWeekDay(String startDate, int week, int dayIndex) {
    final start = DateTime.tryParse(startDate)!;
    return DateTime(start.year, start.month, start.day)
        .add(Duration(days: (week - 1) * 7 + dayIndex));
  }

  static String iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── 课程 ──

  /// 课程是否覆盖某周（weekType: all/odd/even）。
  static bool coversWeek(TtCourse c, int zs) {
    if (zs < c.weekStart || zs > c.weekEnd) return false;
    return switch (c.weekType) {
      'odd' => zs.isOdd,
      'even' => zs.isEven,
      _ => true,
    };
  }

  /// 教务导入课程：从原始周数据推导（合并键刻意不含 code/clazz），id 形如 `jw-<n>`。
  static List<TtCourse> deriveImported(SemesterTt tt) {
    final byKey = <String, List<int>>{};
    final meta = <String, TtCourse>{};
    final weekKeys = tt.jwxtWeeks.keys.map(int.parse).toList()..sort();
    for (final zs in weekKeys) {
      for (final o in tt.jwxtWeeks[zs.toString()] ?? const <TtCourse>[]) {
        final key = '${o.name}|${o.place}|${o.teachers}|${o.day}|${o.slotStart}|${o.slotEnd}';
        byKey.putIfAbsent(key, () => []).add(zs);
        final existing = meta[key];
        // code 取首个非 32 位 GUID 的值（同网站 GUID_RE 规则）
        if (existing == null || (_isGuid(existing.code) && !_isGuid(o.code))) {
          meta[key] = o;
        }
      }
    }
    final out = <TtCourse>[];
    var n = 0;
    for (final e in byKey.entries) {
      final zsList = (e.value.toSet().toList()..sort());
      for (final seg in _splitWeekRuns(zsList)) {
        final m = meta[e.key]!;
        out.add(TtCourse(
          id: 'jw-${n++}',
          name: m.name,
          place: m.place,
          teachers: m.teachers,
          day: m.day,
          slotStart: m.slotStart,
          slotEnd: m.slotEnd,
          weekType: seg.$1,
          weekStart: seg.$2,
          weekEnd: seg.$3,
          code: m.code,
          clazz: m.clazz,
        ));
      }
    }
    out.sort((a, b) => (a.day * 10 + a.slotStart).compareTo(b.day * 10 + b.slotStart));
    return out;
  }

  static final RegExp _guidRe = RegExp(r'^[0-9A-Fa-f]{32}$');
  static bool _isGuid(String s) => _guidRe.hasMatch(s);

  /// 周号集合 → 连续段（相邻差 2 且同奇偶合并；段长 ≥2 全同奇偶 → odd/even）。
  static List<(String, int, int)> _splitWeekRuns(List<int> zsList) {
    final runs = <List<int>>[];
    for (final zs in zsList) {
      if (runs.isNotEmpty && zs - runs.last.last == 1) {
        runs.last.add(zs);
      } else {
        runs.add([zs]);
      }
    }
    // 相邻段首尾差 2 且整体同奇偶 → 合并（如 6,8 → 6-8）
    final merged = <List<int>>[];
    for (final r in runs) {
      if (merged.isNotEmpty &&
          r.first - merged.last.last == 2 &&
          r.first.isOdd == merged.last.first.isOdd) {
        merged.last.addAll(r);
      } else {
        merged.add(r);
      }
    }
    return merged.map((r) {
      final sameParity = r.length >= 2 && r.every((w) => w.isOdd == r.first.isOdd);
      final type = r.length == 1 ? 'all' : (sameParity ? (r.first.isOdd ? 'odd' : 'even') : 'all');
      return (type, r.first, r.last);
    }).toList();
  }

  static String _occKey(TtCourse c) =>
      '${c.name}|${c.place}|${c.teachers}|${c.day}|${c.slotStart}|${c.slotEnd}';

  static bool _sameParity(String weekType, int zs) => switch (weekType) {
        'odd' => zs.isOdd,
        'even' => zs.isEven,
        _ => true,
      };

  /// 编辑教务课程 → 转手动：从原始周数据删除该课程覆盖的周次内的同键场次。
  static void removeImportedSegment(SemesterTt tt, TtCourse c) {
    for (var zs = c.weekStart; zs <= c.weekEnd; zs++) {
      if (!_sameParity(c.weekType, zs)) continue;
      final list = tt.jwxtWeeks['$zs'];
      list?.removeWhere((o) => _occKey(o) == _occKey(c));
      if (list != null && list.isEmpty) tt.jwxtWeeks.remove('$zs');
    }
  }

  /// 删除教务课程：scope='week' 只删某周，scope='all' 删所有周同名场次。
  static void removeImportedOccurrence(SemesterTt tt, TtCourse item, {required bool all, int week = 0}) {
    tt.jwxtWeeks.forEach((zs, list) {
      if (!all && int.parse(zs) != week) return;
      list.removeWhere((o) => all ? o.name == item.name : _occKey(o) == _occKey(item));
    });
    tt.jwxtWeeks.removeWhere((_, list) => list.isEmpty);
  }

  // ── 调休规则 ──

  /// 新条目按 date 覆盖旧条目，整体按日期升序。
  static List<TtAdjust> mergeAdjustments(List<TtAdjust> prev, List<TtAdjust> entries) {
    final dates = entries.map((e) => e.date).toSet();
    final kept = prev.where((a) => !dates.contains(a.date)).toList();
    return [...kept, ...entries]..sort((a, b) => a.date.compareTo(b.date));
  }

  /// 日期区间展开（含两端，上限 42 天）。
  static List<DateTime> expandDateRange(String start, String? end) {
    final s = DateTime.tryParse(start);
    if (s == null) return const [];
    if (end == null || end.isEmpty) return [s];
    final e = DateTime.tryParse(end);
    if (e == null || e.isBefore(s)) return [s];
    final days = e.difference(s).inDays;
    return [for (var i = 0; i <= days && i < 42; i++) s.add(Duration(days: i))];
  }

  // ── 考试 → 日程 ──

  /// 返回实际新增条数。只收学期范围内（startDate..+weekCount*7），键去重。
  static int addExamEvents(SemesterTt tt, List<Map<String, dynamic>> exams) {
    final start = DateTime.tryParse(tt.startDate);
    final end = start?.add(Duration(days: tt.weekCount * 7));
    final keys = tt.events.map((e) => '${e.date}|${e.name}|${e.start}|${e.end}').toSet();
    var added = 0;
    for (final ex in exams) {
      final date = '${ex['date'] ?? ''}';
      if (date.isEmpty) continue;
      final d = DateTime.tryParse(date);
      if (start != null && end != null && d != null && (d.isBefore(start) || !d.isBefore(end))) {
        continue;
      }
      final key = '$date|${ex['name']}|${ex['start']}|${ex['end']}';
      if (keys.contains(key)) continue;
      keys.add(key);
      final seat = '${ex['seat'] ?? ''}';
      tt.events.add(TtEvent(
        id: genId(),
        kind: 'exam',
        name: '${ex['name'] ?? ''}',
        place: '${ex['place'] ?? ''}',
        date: date,
        day: (d?.weekday ?? 1) - 1,
        start: '${ex['start'] ?? ''}',
        end: '${ex['end'] ?? ''}',
        seat: seat,
        note: ['${ex['ksmc'] ?? ''}', if (seat.isNotEmpty) '座位 $seat'].where((s) => s.isNotEmpty).join(' · '),
      ));
      added++;
    }
    return added;
  }

  static String genId() =>
      DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
      (DateTime.now().microsecondsSinceEpoch % 920000).toRadixString(36).padLeft(4, '0');
}

// ── 数据模型（JSON 字段名与网站 store 一致，便于未来云同步互通）──

class TtCourse {
  TtCourse({
    required this.id,
    required this.name,
    required this.day,
    required this.slotStart,
    required this.slotEnd,
    required this.weekType,
    required this.weekStart,
    required this.weekEnd,
    this.place = '',
    this.teachers = '',
    this.code = '',
    this.clazz = '',
  });

  String id;
  String name;
  String place;
  String teachers;
  int day; // 0=周一
  int slotStart; // 大节下标 0-4（0 起，含）
  int slotEnd;
  String weekType; // all / odd / even
  int weekStart; // 1 起
  int weekEnd; // 含
  String code;
  String clazz;

  factory TtCourse.fromJson(Map<String, dynamic> j) => TtCourse(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        place: '${j['place'] ?? ''}',
        teachers: '${j['teachers'] ?? ''}',
        day: asInt(j['day']) ?? 0,
        slotStart: asInt(j['slotStart']) ?? 0,
        slotEnd: asInt(j['slotEnd']) ?? 0,
        weekType: '${j['weekType'] ?? 'all'}',
        weekStart: asInt(j['weekStart']) ?? 1,
        weekEnd: asInt(j['weekEnd']) ?? 1,
        code: '${j['code'] ?? ''}',
        clazz: '${j['clazz'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'place': place, 'teachers': teachers,
        'day': day, 'slotStart': slotStart, 'slotEnd': slotEnd,
        'weekType': weekType, 'weekStart': weekStart, 'weekEnd': weekEnd,
        'code': code, 'clazz': clazz,
      };
}

class TtEvent {
  TtEvent({
    required this.id,
    required this.name,
    required this.date,
    required this.start,
    required this.end,
    this.day = 0,
    this.place = '',
    this.seat = '',
    this.note = '',
    this.kind = '',
  });

  String id;
  String name;
  String place;
  String date; // YYYY-MM-DD；空 = 按星期每周重复
  int day; // 0=周一（date 为空时用于重复匹配）
  String start; // HH:MM
  String end;
  String seat;
  String note;
  String kind; // 'exam' 或空

  factory TtEvent.fromJson(Map<String, dynamic> j) => TtEvent(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        place: '${j['place'] ?? ''}',
        date: '${j['date'] ?? ''}',
        day: asInt(j['day']) ?? 0,
        start: '${j['start'] ?? ''}',
        end: '${j['end'] ?? ''}',
        seat: '${j['seat'] ?? ''}',
        note: '${j['note'] ?? ''}',
        kind: '${j['kind'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'place': place, 'date': date, 'day': day,
        'start': start, 'end': end, 'seat': seat, 'note': note,
        if (kind.isNotEmpty) 'kind': kind,
      };
}

class TtAdjust {
  TtAdjust({required this.date, required this.type, this.day = 0});

  String date; // YYYY-MM-DD，主键
  String type; // off=放假 / follow=按周 X 上课
  int day; // 仅 follow：0=周一

  factory TtAdjust.fromJson(Map<String, dynamic> j) => TtAdjust(
        date: '${j['date'] ?? ''}',
        type: '${j['type'] ?? 'off'}',
        day: asInt(j['day']) ?? 0,
      );

  Map<String, dynamic> toJson() =>
      type == 'follow' ? {'date': date, 'type': type, 'day': day} : {'date': date, 'type': type};
}

class SemesterTt {
  SemesterTt({
    this.name = '',
    this.startDate = '',
    this.weekCount = 20,
    List<TtCourse>? courses,
    List<TtEvent>? events,
    List<TtAdjust>? adjustments,
    Map<String, List<TtCourse>>? jwxtWeeks,
  })  : courses = courses ?? [],
        events = events ?? [],
        adjustments = adjustments ?? [],
        jwxtWeeks = jwxtWeeks ?? {};

  String name;
  String startDate; // 恒为「第 1 周周一」
  int weekCount; // 1-40
  List<TtCourse> courses; // 手动课程
  List<TtEvent> events;
  List<TtAdjust> adjustments;
  Map<String, List<TtCourse>> jwxtWeeks; // 教务原始周数据，键为字符串周号

  factory SemesterTt.fromJson(Map<String, dynamic> j) => SemesterTt(
        name: '${j['name'] ?? ''}',
        startDate: '${j['startDate'] ?? ''}',
        weekCount: asInt(j['weekCount']) ?? 20,
        courses: ((j['courses'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TtCourse.fromJson)
            .toList(),
        events: ((j['events'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TtEvent.fromJson)
            .toList(),
        adjustments: ((j['adjustments'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TtAdjust.fromJson)
            .toList(),
        jwxtWeeks: (((j['jwxt'] as Map<String, dynamic>?)?['weeks']
                    as Map<String, dynamic>?) ??
                {})
            .map((k, v) => MapEntry(
                k,
                ((v as List?) ?? const [])
                    .whereType<Map<String, dynamic>>()
                    .map(TtCourse.fromJson)
                    .toList())),
      );

  Map<String, dynamic> toJson() => {
        'version': 1,
        'name': name,
        'startDate': startDate,
        'weekCount': weekCount,
        'courses': courses.map((c) => c.toJson()).toList(),
        'events': events.map((e) => e.toJson()).toList(),
        'adjustments': adjustments.map((a) => a.toJson()).toList(),
        'jwxt': {'weeks': jwxtWeeks.map((k, v) => MapEntry(k, v.map((c) => c.toJson()).toList()))},
      };
}
