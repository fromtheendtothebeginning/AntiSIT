import 'json_num.dart';

/// 一门课的学期内排课（JSON 字段名与网站 store 一致，便于云同步互通）。
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
    'id': id,
    'name': name,
    'place': place,
    'teachers': teachers,
    'day': day,
    'slotStart': slotStart,
    'slotEnd': slotEnd,
    'weekType': weekType,
    'weekStart': weekStart,
    'weekEnd': weekEnd,
    'code': code,
    'clazz': clazz,
  };
}

/// 一条日程（考试 / 自定义事项）：单次，或每周 / 每两周 / 每月重复。
///
/// 老数据靠「[date] 为空 = 每周重复」区分单次与重复；现在显式写成 [repeat]，
/// 缺字段的老数据在 [TtEvent.fromJson] 里按同一规则换算，升级后课表不会变形。
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
    String? repeat,
    this.repeatStart = '',
    this.repeatEnd = '',
  }) : repeat = _normRepeat(repeat, date);

  /// 重复类型取值。
  static const String repeatNone = 'none';
  static const String repeatWeekly = 'weekly';
  static const String repeatBiweekly = 'biweekly';
  static const String repeatMonthly = 'monthly';

  String id;
  String name;
  String place;

  /// 单次日程的日期（YYYY-MM-DD）；重复日程留空，与老数据同一套语义。
  String date;

  /// 0=周一（重复日程的星期；单次日程另外存所选日期对应的星期）。
  int day;

  String start; // HH:MM
  String end;
  String seat;
  String note;
  String kind; // 'exam' 或空

  /// 重复类型：none（单次）/ weekly / biweekly / monthly。
  String repeat;

  /// 循环开始日期（YYYY-MM-DD）；空 = 不限期（可以一直排到学期末）。
  String repeatStart;

  /// 循环结束日期（YYYY-MM-DD）；空 = 学期末，由调用方按日期范围判断。
  String repeatEnd;

  /// 是否重复日程（每周 / 每两周 / 每月）。
  bool get isRepeating => repeat.isNotEmpty && repeat != repeatNone;

  /// 重复类型的短名：单次 / 每周 / 每两周 / 每月。
  String get repeatLabel => switch (repeat) {
    repeatWeekly => '每周',
    repeatBiweekly => '每两周',
    repeatMonthly => '每月',
    _ => '单次',
  };

  /// 去重键：同名同时间的同一天算同一条（考试导入 / 日历导入共用）。
  ///
  /// 单次日程与老格式一致；重复日程额外带上重复类型与星期，免得两条不同的
  /// 每周日程（同名字同时刻）被误判成重复。
  String get dedupeKey => isRepeating
      ? '$repeat|$day|$repeatStart|$repeatEnd|$name|$start|$end'
      : '$date|$name|$start|$end';

  /// 归一重复类型：空串（老数据）或未知值按老规则推断——日期为空算每周，否则单次。
  static String _normRepeat(String? v, String date) {
    final s = (v ?? '').trim();
    if (s == repeatNone ||
        s == repeatWeekly ||
        s == repeatBiweekly ||
        s == repeatMonthly) {
      return s;
    }
    return date.isEmpty ? repeatWeekly : repeatNone;
  }

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
    repeat: '${j['repeat'] ?? ''}',
    repeatStart: '${j['repeatStart'] ?? ''}',
    repeatEnd: '${j['repeatEnd'] ?? ''}',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'place': place,
    'date': date,
    'day': day,
    'start': start,
    'end': end,
    'seat': seat,
    'note': note,
    if (kind.isNotEmpty) 'kind': kind,
    'repeat': repeat,
    'repeatStart': repeatStart,
    'repeatEnd': repeatEnd,
  };

  /// 这条日程在 [date] 这一天是否发生（只判日期，不看时刻）。
  ///
  /// 重复日程的上界由调用方裁剪：repeatEnd 为空表示「排到学期末」，调用方按
  /// 自己关心的日期范围（学期 / 提醒窗口 / 筛选区间）截断即可。
  /// [semesterStart] 只在 repeatStart 为空时当锚点（每两周的单双周 / 每月的几号）。
  bool occursOn(DateTime date, {required DateTime semesterStart}) =>
      _occursOn(date, semesterStart: semesterStart);

  /// [occursOn] 的扩展：调休把某一天换成别的星期几时，课表页 / 导出按「这一列
  /// 实际上的是星期几」判——[weekdayOverride] 就是那个星期（0=周一，null = 放假）。
  /// 每月重复锚在日期上，不看这个（每月几号与星期几无关）。
  bool occursOnColumn(
    DateTime date, {
    required DateTime semesterStart,
    required int? weekdayOverride,
  }) => _occursOn(
    date,
    semesterStart: semesterStart,
    weekday: weekdayOverride,
    requireWeekday: true,
  );

  bool _occursOn(
    DateTime date, {
    required DateTime semesterStart,
    int? weekday,
    bool requireWeekday = false,
  }) {
    final at = DateTime(date.year, date.month, date.day);
    if (at.year <= 1970) return false; // 占位 / 非法日期
    if (!isRepeating) {
      final once = _isoDate(this.date);
      return once != null && once == at;
    }
    // 调休放假（这一列没有课）：当天的日程也跟着这一列走，不显示。
    if (requireWeekday && weekday == null) return false;
    final from = _isoDate(repeatStart);
    final to = _isoDate(repeatEnd);
    if (from != null && at.isBefore(from)) return false;
    if (to != null && at.isAfter(to)) return false;
    final anchor =
        from ??
        DateTime(semesterStart.year, semesterStart.month, semesterStart.day);
    final wd = weekday ?? (at.weekday - 1);
    return switch (repeat) {
      repeatWeekly => wd == day,
      repeatBiweekly => wd == day && _weekIndex(at, anchor).isEven,
      repeatMonthly => _isMonthDay(at, anchor),
      _ => false,
    };
  }

  /// [from] 起（含）[limitDays] 天内最近的一次发生；没有返回 null。
  ///
  /// 单次日程直接比日期，重复日程逐日判（上限 400 天，够覆盖一个学年）。
  DateTime? nextOccurrence(
    DateTime from, {
    required DateTime semesterStart,
    int limitDays = 400,
  }) {
    final start = DateTime(from.year, from.month, from.day);
    final limit = limitDays.clamp(0, 400);
    final stop = start.add(Duration(days: limit));
    if (!isRepeating) {
      final once = _isoDate(date);
      if (once == null || once.isBefore(start) || once.isAfter(stop)) {
        return null;
      }
      return once;
    }
    var at = start;
    while (!at.isAfter(stop)) {
      if (occursOn(at, semesterStart: semesterStart)) return at;
      at = at.add(const Duration(days: 1));
    }
    return null;
  }

  /// [from, to] 里（含两端）有没有一次发生（日程筛选 / 近期日程用）。
  bool occursBetween(
    DateTime from,
    DateTime to, {
    required DateTime semesterStart,
  }) {
    final f = DateTime(from.year, from.month, from.day);
    final t = DateTime(to.year, to.month, to.day);
    if (t.isBefore(f)) return false;
    final days = DateTime.utc(
      t.year,
      t.month,
      t.day,
    ).difference(DateTime.utc(f.year, f.month, f.day)).inDays;
    return nextOccurrence(f, semesterStart: semesterStart, limitDays: days) !=
        null;
  }

  /// 两个日期相隔几周（各自所在周（周一起）之差；UTC 日算，绕开时区 / 夏令时）。
  static int _weekIndex(DateTime a, DateTime b) {
    int monday(DateTime d) {
      final day = DateTime.utc(d.year, d.month, d.day);
      return day
              .subtract(Duration(days: d.weekday - 1))
              .millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay;
    }

    return (monday(a) - monday(b)) ~/ 7;
  }

  /// 每月的第几天：取锚点的「日」，当月没有这一天时取当月最后一天。
  static bool _isMonthDay(DateTime at, DateTime anchor) {
    final lastDay = DateTime(at.year, at.month + 1, 0).day;
    final want = anchor.day <= lastDay ? anchor.day : lastDay;
    return at.day == want;
  }

  /// 解析 YYYY-MM-DD 成当天 0 点；空 / 非法 / 1970 年以前返回 null。
  static DateTime? _isoDate(String s) {
    final t = s.trim();
    if (t.length < 8) return null;
    final d = DateTime.tryParse(t);
    if (d == null || d.year <= 1970) return null;
    return DateTime(d.year, d.month, d.day);
  }
}

/// 一条调休规则：某天放假，或按另一个星期几上课。
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

  Map<String, dynamic> toJson() => type == 'follow'
      ? {'date': date, 'type': type, 'day': day}
      : {'date': date, 'type': type};
}

/// 一个学期的完整课表：手动课程 + 日程 + 调休规则 + 教务原始周数据。
class SemesterTt {
  SemesterTt({
    this.name = '',
    this.startDate = '',
    this.weekCount = 20,
    List<TtCourse>? courses,
    List<TtEvent>? events,
    List<TtAdjust>? adjustments,
    Map<String, List<TtCourse>>? jwxtWeeks,
  }) : courses = courses ?? [],
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
    jwxtWeeks:
        (((j['jwxt'] as Map<String, dynamic>?)?['weeks']
                    as Map<String, dynamic>?) ??
                {})
            .map(
              (k, v) => MapEntry(
                k,
                ((v as List?) ?? const [])
                    .whereType<Map<String, dynamic>>()
                    .map(TtCourse.fromJson)
                    .toList(),
              ),
            ),
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'name': name,
    'startDate': startDate,
    'weekCount': weekCount,
    'courses': courses.map((c) => c.toJson()).toList(),
    'events': events.map((e) => e.toJson()).toList(),
    'adjustments': adjustments.map((a) => a.toJson()).toList(),
    'jwxt': {
      'weeks': jwxtWeeks.map(
        (k, v) => MapEntry(k, v.map((c) => c.toJson()).toList()),
      ),
    },
  };
}
