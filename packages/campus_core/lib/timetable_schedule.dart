import 'timetable_models.dart';

// 学期换算 / 周次判定 / 课程推导的纯函数：不碰持久化，也不依赖 store 的单例状态。
// `TimetableStore` 上的同名静态成员只是转发到这里（对外契约不变）。

/// 学期 key：`学年-学期码`（正方：3=第一学期 / 12=第二学期 / 16=短学期）。
String ttSemesterKeyOf(DateTime? start) {
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
int? ttLocateToday(String? startDate, int weekCount) {
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

/// 今天是周几（0 = 周一）。
int ttTodayDayIndex() => DateTime.now().weekday - 1;

/// [now] 所在周（[startDate] 为第 1 周周一）；不在学期内返回 null。
int? ttWeekOf(String startDate, int weekCount, DateTime now) {
  final start = DateTime.tryParse(startDate);
  if (start == null || start.year <= 1970 || weekCount <= 0) return null;
  final s0 = DateTime(start.year, start.month, start.day);
  final n0 = DateTime(now.year, now.month, now.day);
  final week = n0.difference(s0).inDays ~/ 7 + 1;
  if (week < 1 || week > weekCount) return null;
  return week;
}

/// 下课时刻是否已过（课表页「已上过的课置灰」依据）。
/// [colISO] 是**纯日期**（yyyy-MM-dd），必须把 hh:mm 拼上去再比，否则永判「还没下课」。
bool ttLessonPassed(String colISO, String endHHmm, {DateTime? now}) {
  final day = DateTime.tryParse(colISO);
  if (day == null) return false;
  final parts = endHHmm.split(':');
  if (parts.length != 2) return false;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return false;
  return DateTime(
    day.year,
    day.month,
    day.day,
    h,
    m,
  ).isBefore(now ?? DateTime.now());
}

/// 某周某天「还没上完」的课，按上课时刻升序（课表顶部「今天最近一节课」用）。
/// [startDate] 为空（未设置学期起点）时无从判断日期，原样返回。
List<TtCourse> ttUpcomingOn(
  List<TtCourse> courses, {
  required String startDate,
  required int week,
  required int dayIndex,
  required List<String> endTimes,
  DateTime? now,
}) {
  if (startDate.isEmpty) return List.of(courses);
  final t = now ?? DateTime.now();
  final colISO = ttIso(ttDateOfWeekDay(startDate, week, dayIndex));
  return courses
      .where(
        (c) => !ttLessonPassed(
          colISO,
          endTimes[c.slotEnd.clamp(0, endTimes.length - 1)],
          now: t,
        ),
      )
      .toList()
    ..sort((a, b) => a.slotStart.compareTo(b.slotStart));
}

/// 某周某天「已经上完」的课，按上课时刻升序（顶部卡片里这些课淡显）。
List<TtCourse> ttPastOn(
  List<TtCourse> courses, {
  required String startDate,
  required int week,
  required int dayIndex,
  required List<String> endTimes,
  DateTime? now,
}) {
  if (startDate.isEmpty) return const [];
  final t = now ?? DateTime.now();
  final colISO = ttIso(ttDateOfWeekDay(startDate, week, dayIndex));
  return courses
      .where(
        (c) => ttLessonPassed(
          colISO,
          endTimes[c.slotEnd.clamp(0, endTimes.length - 1)],
          now: t,
        ),
      )
      .toList()
    ..sort((a, b) => a.slotStart.compareTo(b.slotStart));
}

/// 学期第 [week] 周第 [dayIndex] 天（0 = 周一）的日期。
DateTime ttDateOfWeekDay(String startDate, int week, int dayIndex) {
  final start = DateTime.tryParse(startDate)!;
  return DateTime(
    start.year,
    start.month,
    start.day,
  ).add(Duration(days: (week - 1) * 7 + dayIndex));
}

/// `yyyy-MM-dd`。
String ttIso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 课程是否覆盖某周（weekType: all/odd/even）。
bool ttCoversWeek(TtCourse c, int zs) {
  if (zs < c.weekStart || zs > c.weekEnd) return false;
  return switch (c.weekType) {
    'odd' => zs.isOdd,
    'even' => zs.isEven,
    _ => true,
  };
}

/// 教务导入课程：从原始周数据推导（合并键刻意不含 code/clazz），id 形如 `jw-<n>`。
List<TtCourse> ttDeriveImported(SemesterTt tt) {
  final byKey = <String, List<int>>{};
  final meta = <String, TtCourse>{};
  final weekKeys = tt.jwxtWeeks.keys.map(int.parse).toList()..sort();
  for (final zs in weekKeys) {
    for (final o in tt.jwxtWeeks[zs.toString()] ?? const <TtCourse>[]) {
      final key =
          '${o.name}|${o.place}|${o.teachers}|${o.day}|${o.slotStart}|${o.slotEnd}';
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
      out.add(
        TtCourse(
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
        ),
      );
    }
  }
  out.sort(
    (a, b) => (a.day * 10 + a.slotStart).compareTo(b.day * 10 + b.slotStart),
  );
  return out;
}

final RegExp _guidRe = RegExp(r'^[0-9A-Fa-f]{32}$');
bool _isGuid(String s) => _guidRe.hasMatch(s);

/// 周号集合 → 连续段（相邻差 2 且同奇偶合并；段长 ≥2 全同奇偶 → odd/even）。
List<(String, int, int)> _splitWeekRuns(List<int> zsList) {
  final runs = <List<int>>[];
  for (final zs in zsList) {
    if (runs.isNotEmpty && zs - runs.last.last == 1) {
      runs.last.add(zs);
    } else {
      runs.add([zs]);
    }
  }
  // 间隔 2 且同奇偶的相邻段合并（如 6,8 → 双周 6-8）；两段都必须是单奇偶，
  // 否则并成 all 会把中间缺席的周画出来。
  final merged = <List<int>>[];
  for (final r in runs) {
    if (merged.isNotEmpty &&
        r.first - merged.last.last == 2 &&
        merged.last.every((w) => w.isOdd == r.first.isOdd) &&
        r.every((w) => w.isOdd == r.first.isOdd)) {
      merged.last.addAll(r);
    } else {
      merged.add(r);
    }
  }
  return merged.map((r) {
    final sameParity =
        r.length >= 2 && r.every((w) => w.isOdd == r.first.isOdd);
    final type = r.length == 1
        ? 'all'
        : (sameParity ? (r.first.isOdd ? 'odd' : 'even') : 'all');
    return (type, r.first, r.last);
  }).toList();
}

String _occKey(TtCourse c) =>
    '${c.name}|${c.place}|${c.teachers}|${c.day}|${c.slotStart}|${c.slotEnd}';

bool _sameParity(String weekType, int zs) => switch (weekType) {
  'odd' => zs.isOdd,
  'even' => zs.isEven,
  _ => true,
};

/// 编辑教务课程 → 转手动：从原始周数据删除该课程覆盖的周次内的同键场次。
void ttRemoveImportedSegment(SemesterTt tt, TtCourse c) {
  for (var zs = c.weekStart; zs <= c.weekEnd; zs++) {
    if (!_sameParity(c.weekType, zs)) continue;
    final list = tt.jwxtWeeks['$zs'];
    list?.removeWhere((o) => _occKey(o) == _occKey(c));
    if (list != null && list.isEmpty) tt.jwxtWeeks.remove('$zs');
  }
}

/// 删除教务课程：all=true 删所有周同名场次，否则只删第 [week] 周的同键场次。
void ttRemoveImportedOccurrence(
  SemesterTt tt,
  TtCourse item, {
  required bool all,
  int week = 0,
}) {
  tt.jwxtWeeks.forEach((zs, list) {
    if (!all && int.parse(zs) != week) return;
    list.removeWhere(
      (o) => all ? o.name == item.name : _occKey(o) == _occKey(item),
    );
  });
  tt.jwxtWeeks.removeWhere((_, list) => list.isEmpty);
}

/// 新条目按 date 覆盖旧条目，整体按日期升序。
List<TtAdjust> ttMergeAdjustments(List<TtAdjust> prev, List<TtAdjust> entries) {
  final dates = entries.map((e) => e.date).toSet();
  final kept = prev.where((a) => !dates.contains(a.date)).toList();
  return [...kept, ...entries]..sort((a, b) => a.date.compareTo(b.date));
}

/// 日期区间展开（含两端，上限 42 天）。
List<DateTime> ttExpandDateRange(String start, String? end) {
  final s = DateTime.tryParse(start);
  if (s == null) return const [];
  if (end == null || end.isEmpty) return [s];
  final e = DateTime.tryParse(end);
  if (e == null || e.isBefore(s)) return [s];
  final days = e.difference(s).inDays;
  return [for (var i = 0; i <= days && i < 42; i++) s.add(Duration(days: i))];
}

/// 把考试排进日程，返回实际新增条数；只收学期范围内，键去重。
///
/// 导入的考试一律是单次日程（repeat 写 none）；去重键走 [TtEvent.dedupeKey]，
/// 重复日程占着「日期 + 星期」那几段，不会和单次考试误撞。
int ttAddExamEvents(SemesterTt tt, List<Map<String, dynamic>> exams) {
  final start = DateTime.tryParse(tt.startDate);
  final end = start?.add(Duration(days: tt.weekCount * 7));
  final keys = tt.events.map((e) => e.dedupeKey).toSet();
  var added = 0;
  for (final ex in exams) {
    final date = '${ex['date'] ?? ''}';
    if (date.isEmpty) continue;
    final d = DateTime.tryParse(date);
    if (start != null &&
        end != null &&
        d != null &&
        (d.isBefore(start) || !d.isBefore(end))) {
      continue;
    }
    final seat = '${ex['seat'] ?? ''}';
    final ev = TtEvent(
      id: ttGenId(),
      kind: 'exam',
      name: '${ex['name'] ?? ''}',
      place: '${ex['place'] ?? ''}',
      date: date,
      day: (d?.weekday ?? 1) - 1,
      start: '${ex['start'] ?? ''}',
      end: '${ex['end'] ?? ''}',
      seat: seat,
      note: [
        '${ex['ksmc'] ?? ''}',
        if (seat.isNotEmpty) '座位 $seat',
      ].where((s) => s.isNotEmpty).join(' · '),
      repeat: TtEvent.repeatNone,
    );
    if (!keys.add(ev.dedupeKey)) continue;
    tt.events.add(ev);
    added++;
  }
  return added;
}

/// 生成一个不会碰撞的本地 id。
String ttGenId() =>
    DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
    (DateTime.now().microsecondsSinceEpoch % 920000)
        .toRadixString(36)
        .padLeft(4, '0');

/// 学期起点（第 1 周周一）的当天 0 点；没设 / 解析不出返回 null。
DateTime? ttSemesterStart(SemesterTt tt) {
  final d = DateTime.tryParse(tt.startDate);
  if (d == null || d.year <= 1970) return null;
  return DateTime(d.year, d.month, d.day);
}

/// 学期最后一天（第 weekCount 周周日）的当天 0 点；没设起点返回 null。
DateTime? ttSemesterEnd(SemesterTt tt) {
  final start = ttSemesterStart(tt);
  if (start == null) return null;
  final weeks = tt.weekCount.clamp(1, 60);
  return start.add(Duration(days: weeks * 7 - 1));
}

/// 这条日程在 [date] 这一天是否发生（单次 / 每周 / 每两周 / 每月统一入口）。
///
/// 日程是日历事件：调休只换课表，不影响日程；学期起点没设时只有单次判得出来。
bool ttEventOccursOn(SemesterTt tt, TtEvent e, DateTime date) {
  final start = ttSemesterStart(tt);
  if (start == null) return !e.isRepeating && e.date == ttIso(date);
  return e.occursOn(date, semesterStart: start);
}

/// 这条日程在 [from, to]（含两端）里有没有一次发生；学期起点没设时只判单次。
bool ttEventOccursBetween(
  SemesterTt tt,
  TtEvent e,
  DateTime from,
  DateTime to,
) {
  final start = ttSemesterStart(tt);
  if (start == null) {
    final once = DateTime.tryParse(e.date);
    if (e.isRepeating || once == null) return false;
    final d = DateTime(once.year, once.month, once.day);
    return !d.isBefore(from) && !d.isAfter(to);
  }
  return e.occursBetween(from, to, semesterStart: start);
}

/// [from] 起（含）最近的一次发生，最多看 [limitDays] 天；没有返回 null。
DateTime? ttEventNextOccurrence(
  SemesterTt tt,
  TtEvent e,
  DateTime from, {
  int limitDays = 400,
}) {
  final start = ttSemesterStart(tt);
  if (start == null) {
    final once = DateTime.tryParse(e.date);
    if (e.isRepeating || once == null) return null;
    final d = DateTime(once.year, once.month, once.day);
    final f = DateTime(from.year, from.month, from.day);
    return d.isBefore(f) ? null : d;
  }
  return e.nextOccurrence(from, semesterStart: start, limitDays: limitDays);
}
