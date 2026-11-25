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
        'id': id, 'name': name, 'place': place, 'teachers': teachers,
        'day': day, 'slotStart': slotStart, 'slotEnd': slotEnd,
        'weekType': weekType, 'weekStart': weekStart, 'weekEnd': weekEnd,
        'code': code, 'clazz': clazz,
      };
}

/// 一条日程（考试 / 自定义事项）：有具体日期，或按星期每周重复。
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

  Map<String, dynamic> toJson() =>
      type == 'follow' ? {'date': date, 'type': type, 'day': day} : {'date': date, 'type': type};
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
