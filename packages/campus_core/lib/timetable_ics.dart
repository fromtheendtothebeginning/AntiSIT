import 'dart:convert';

import 'timetable_store.dart';

/// 课表 ↔ 日历文件（iCalendar，RFC 5545）。
///
/// 一律展开成逐次发生的 VEVENT（不写 RRULE）：单双周 / 周次区间 / 调休在
/// 各客户端都能正确显示。时间用本地浮动时刻（不带 Z / TZID），另附
/// `X-WR-TIMEZONE:Asia/Shanghai`；折行与转义按 RFC 5545。
class TimetableIcs {
  const TimetableIcs._();

  static const _prodId = '-//AntiSIT//课表//CN';
  static const _timezone = 'Asia/Shanghai';
  static const _lineEnd = '\r\n';

  // ── 导出 ──

  /// 一段范围内逐次发生的课 / 日程（导出的一条 VEVENT）。
  static List<TtOccurrence> occurrences({
    required SemesterTt tt,
    required List<TtCourse> courses,
    required List<TtEvent> events,
    required IcsScope scope,
    required List<String> slotStarts,
    required List<String> slotEnds,
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();
    final (from, to) = scope.range(now, tt);
    final out = <TtOccurrence>[];
    final start0 = DateTime.tryParse(tt.startDate);
    if (start0 == null || start0.year <= 1970) return out; // 没设学期起点：算不出日期
    final start = DateTime(start0.year, start0.month, start0.day);
    final weeks = tt.weekCount.clamp(1, 40);
    // 学期最后一天：重复日程没写结束日期时就排到这里（写进 RRULE 的 UNTIL）。
    final semesterEnd = start.add(Duration(days: weeks * 7 - 1));

    // 逐「列」（某周某天）走，和课表页同一套：调休把这一列换成别的星期几，或整列放假。
    for (var week = 1; week <= weeks; week++) {
      for (var day = 0; day < 7; day++) {
        final date = start.add(Duration(days: (week - 1) * 7 + day));
        if (date.isBefore(from) || date.isAfter(to)) continue;
        final eff = _effectiveDay(tt, date, day);
        if (eff != null) {
          for (final c in courses) {
            if (c.day != eff || !TimetableStore.coversWeek(c, week)) continue;
            out.add(_courseOccurrence(c, date, week, slotStarts, slotEnds));
          }
        }
        // 重复日程不走「逐列铺开」：它们与调休无关，见下面的单独一轮。
      }
    }
    // 重复日程只导出一条（带 RRULE），其余场次交给日历客户端铺开。
    // 它不受调休影响：调休换的是「上哪天的课」，日历事件到日子就发生。
    for (final e in events) {
      if (!e.isRepeating) continue;
      var day = DateTime(from.year, from.month, from.day);
      while (!day.isAfter(to)) {
        if (e.occursOn(day, semesterStart: start)) {
          out.add(_eventOccurrence(e, day, semesterEnd: semesterEnd));
          break;
        }
        day = day.add(const Duration(days: 1));
      }
    }
    // 单次日程按日期本身出现（放假也照常显示，与课表页一致）
    for (final e in events) {
      if (e.isRepeating) continue;
      final d = DateTime.tryParse(e.date);
      if (d == null) continue;
      final day = DateTime(d.year, d.month, d.day);
      if (day.isBefore(from) || day.isAfter(to)) continue;
      out.add(_eventOccurrence(e, day));
    }
    out.sort(
      (a, b) => a.date != b.date
          ? a.date.compareTo(b.date)
          : a.startMin.compareTo(b.startMin),
    );
    return out;
  }

  /// 生成 .ics 文本（CRLF 换行，UTF-8 编码后写文件即可）。
  static String build({
    required SemesterTt tt,
    required List<TtCourse> courses,
    required List<TtEvent> events,
    required IcsScope scope,
    required List<String> slotStarts,
    required List<String> slotEnds,
    String calendarName = '',
    DateTime? now,
  }) {
    final stamp = now ?? DateTime.now();
    final items = occurrences(
      tt: tt,
      courses: courses,
      events: events,
      scope: scope,
      slotStarts: slotStarts,
      slotEnds: slotEnds,
      today: stamp,
    );
    final name = calendarName.isNotEmpty
        ? calendarName
        : [
            'AntiSIT 课表',
            if (tt.name.isNotEmpty) tt.name,
            scope.label,
          ].join(' ');
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:$_prodId',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:${_esc(name)}',
      'X-WR-TIMEZONE:$_timezone',
      for (final o in items) ..._vevent(o, stamp),
      'END:VCALENDAR',
    ];
    return lines.map(_fold).join(_lineEnd) + _lineEnd;
  }

  static List<String> _vevent(TtOccurrence o, DateTime stamp) {
    final start = o.date.add(Duration(minutes: o.startMin));
    final end = o.date.add(Duration(minutes: o.endMin));
    return [
      'BEGIN:VEVENT',
      'UID:${o.uid}',
      'DTSTAMP:${_utcStamp(stamp)}',
      'DTSTART:${_floating(start)}',
      'DTEND:${_floating(end)}',
      if (o.rrule.isNotEmpty) 'RRULE:${o.rrule}',
      'SUMMARY:${_esc(o.title)}',
      if (o.place.isNotEmpty) 'LOCATION:${_esc(o.place)}',
      if (o.description.isNotEmpty) 'DESCRIPTION:${_esc(o.description)}',
      'END:VEVENT',
    ];
  }

  /// 重复日程的 RRULE：每周 / 每两周 / 每月；[until] 为空就不写 UNTIL（不限次）。
  ///
  /// UNTIL 落在 repeatEnd 的次日 0 点（本地浮动，与 DTSTART 同一套写法），
  /// 表示「repeatEnd 当天这次也算」；用日期型 UNTIL 各客户端解释不一致。
  static String _rruleOf(String repeat, DateTime? until) {
    final suffix = until == null
        ? ''
        : ';UNTIL=${_floating(until.add(const Duration(days: 1)))}';
    return switch (repeat) {
      TtEvent.repeatWeekly => 'FREQ=WEEKLY$suffix',
      TtEvent.repeatBiweekly => 'FREQ=WEEKLY;INTERVAL=2$suffix',
      TtEvent.repeatMonthly => 'FREQ=MONTHLY$suffix',
      _ => '',
    };
  }

  static TtOccurrence _courseOccurrence(
    TtCourse c,
    DateTime date,
    int week,
    List<String> slotStarts,
    List<String> slotEnds,
  ) {
    final s = c.slotStart.clamp(0, slotStarts.length - 1);
    final e = c.slotEnd.clamp(s, slotEnds.length - 1);
    final desc = <String>[
      if (c.teachers.isNotEmpty) '教师：${c.teachers}',
      '第 $week 周（${_weekTypeText(c.weekType)}，第 ${c.weekStart}-${c.weekEnd} 周）',
      '第 ${c.slotStart + 1}-${c.slotEnd + 1} 节',
      if (c.clazz.isNotEmpty) '班级：${c.clazz}',
    ];
    return TtOccurrence(
      uid:
          'antisit-course-${c.id}-${_dayStamp(date)}T${_hhmm(slotStarts[s])}@antisit',
      title: c.name,
      place: c.place,
      description: desc.join('\n'),
      date: date,
      startMin: _minutes(slotStarts[s]),
      endMin: _minutes(slotEnds[e]),
      isEvent: false,
    );
  }

  static TtOccurrence _eventOccurrence(
    TtEvent e,
    DateTime date, {
    DateTime? semesterEnd,
  }) {
    final start = _minutes(e.start);
    final end = _minutes(e.end);
    // 结束时界：repeatEnd 有就用到那天；没写就按学期末——不写 UNTIL 等于排到天荒地老。
    final until = DateTime.tryParse(e.repeatEnd) ?? semesterEnd;
    final desc = [
      if (e.kind == 'exam') '考试',
      if (e.isRepeating) '重复：${e.repeatLabel}',
      if (e.place.isNotEmpty) '地点：${e.place}',
      if (e.seat.isNotEmpty) '座位：${e.seat}',
      if (e.note.isNotEmpty) e.note,
    ];
    return TtOccurrence(
      uid: 'antisit-event-${e.id}@antisit',
      title: e.name,
      place: e.place,
      description: desc.join('\n'),
      date: date,
      // 没填时刻（全天）：按 00:00-23:59 摆放
      startMin: start < 0 ? 0 : start,
      endMin: end < 0 ? 1439 : end,
      isEvent: true,
      rrule: e.isRepeating ? _rruleOf(e.repeat, until) : '',
    );
  }

  /// 某一天按课表实际该上星期几的课：off = 放假（null），follow = 按另一天，否则自己。
  static int? _effectiveDay(SemesterTt tt, DateTime date, int day) {
    final iso = TimetableStore.iso(date);
    for (final a in tt.adjustments) {
      if (a.date != iso) continue;
      return a.type == 'off' ? null : a.day;
    }
    return day;
  }

  static String _weekTypeText(String t) => switch (t) {
    'odd' => '单周',
    'even' => '双周',
    _ => '每周',
  };

  // ── 导入 ──

  /// 解析 .ics 文本 → 逐条事件（[IcsEvent]）。坏行跳过，不整份失败。
  static List<IcsEvent> parse(String text) {
    final out = <IcsEvent>[];
    Map<String, ({String value, Map<String, String> params})>? cur;
    for (final line in _unfold(text)) {
      if (line.startsWith('BEGIN:VEVENT')) {
        cur = {};
        continue;
      }
      if (line.startsWith('END:VEVENT')) {
        final e = _toEvent(cur ?? const {});
        if (e != null) out.addAll(e);
        cur = null;
        continue;
      }
      if (cur == null) continue;
      final (name, value, params) = _splitProperty(line);
      if (name.isNotEmpty) cur[name] = (value: value, params: params);
    }
    return out;
  }

  /// 一条 VEVENT → 一至多条事件：简单「每周重复」折成「每周日程」（date 空 + 星期几）；
  /// 带 COUNT / UNTIL 的展开成逐条；复杂重复规则只取首次发生并标记 simplified。
  static List<IcsEvent>? _toEvent(
    Map<String, ({String value, Map<String, String> params})> props,
  ) {
    final start = _parseDate(props['DTSTART']);
    if (start == null) return null;
    final end = _parseDate(props['DTEND']);
    final allDay = start.allDay;
    var startMin = allDay ? 0 : start.date.hour * 60 + start.date.minute;
    var endMin = allDay
        ? 1439
        : (end != null ? end.date.hour * 60 + end.date.minute : startMin + 45);
    if (endMin < startMin) endMin = startMin;

    String text(String key) => _unesc(props[key]?.value ?? '');
    final rule = _parseRrule(props['RRULE']?.value ?? '');
    final base = (
      summary: text('SUMMARY'),
      location: text('LOCATION'),
      description: text('DESCRIPTION'),
      uid: props['UID']?.value ?? '',
    );
    final weekdays = rule.byDay.map(_weekdayOf).whereType<int>().toList();
    // 导入只认「每周」这一种（与导出侧一致：每两周 / 每月导出的是具体日期，
    // 导回来就是一条条单次日程）。其它频率一律只取首次并标记 simplified。
    final repeat =
        rule.freq == 'WEEKLY' && rule.interval <= 1 && weekdays.length <= 1
        ? TtEvent.repeatWeekly
        : '';
    final repeatEnd = rule.until == null ? '' : TimetableStore.iso(rule.until!);

    IcsEvent make(
      DateTime date,
      int? weeklyDay,
      bool simplified, {
      String repeatKind = TtEvent.repeatWeekly,
      String until = '',
      String anchor = '',
    }) {
      final day = DateTime(date.year, date.month, date.day); // 只留日期，时刻另存
      return IcsEvent(
        summary: base.summary,
        location: base.location,
        description: base.description,
        uid: base.uid,
        date: weeklyDay == null ? day : null,
        weekday: weeklyDay ?? day.weekday - 1,
        startMin: startMin,
        endMin: endMin,
        allDay: allDay,
        simplified: simplified,
        repeat: repeatKind,
        repeatStart: anchor,
        repeatEnd: until,
      );
    }

    if (repeat.isEmpty) {
      // 按年 / 多星期几 / 其它间隔：只取首次发生
      final simplified = rule.freq.isNotEmpty || rule.interval > 1;
      return [make(start.date, null, simplified)];
    }
    if (rule.count == null) {
      // 没有次数上限：折成一条重复日程（date 空 + 重复类型 + 星期几）
      final wd = weekdays.isNotEmpty ? weekdays.first : start.date.weekday - 1;
      return [
        make(
          start.date,
          wd,
          false,
          repeatKind: repeat,
          until: repeatEnd,
          anchor: TimetableStore.iso(start.date),
        ),
      ];
    }
    final out = <IcsEvent>[];
    var date = start.date;
    for (var i = 0; i < 200; i++) {
      if (rule.count != null && i >= rule.count!) break;
      if (rule.until != null && date.isAfter(rule.until!)) break;
      out.add(make(date, null, false));
      date = date.add(const Duration(days: 7));
    }
    return out;
  }

  static int? _weekdayOf(String byDay) {
    const map = {'MO': 0, 'TU': 1, 'WE': 2, 'TH': 3, 'FR': 4, 'SA': 5, 'SU': 6};
    final key = byDay.replaceAll(RegExp(r'^[+-]?\d+'), '').toUpperCase();
    return map[key];
  }

  static ({
    String freq,
    int interval,
    int? count,
    DateTime? until,
    List<String> byDay,
  })
  _parseRrule(String raw) {
    var freq = '';
    var interval = 1;
    int? count;
    DateTime? until;
    final byDay = <String>[];
    for (final part in raw.split(';')) {
      final i = part.indexOf('=');
      if (i < 0) continue;
      final k = part.substring(0, i).toUpperCase();
      final v = part.substring(i + 1).trim();
      switch (k) {
        case 'FREQ':
          freq = v.toUpperCase();
        case 'INTERVAL':
          interval = int.tryParse(v) ?? 1;
        case 'COUNT':
          count = int.tryParse(v);
        case 'UNTIL':
          until = _parseDate((value: v, params: const {}))?.date;
        case 'BYDAY':
          byDay.addAll(v.split(',').where((s) => s.isNotEmpty));
      }
    }
    return (
      freq: freq,
      interval: interval,
      count: count,
      until: until,
      byDay: byDay,
    );
  }

  /// 日期 / 日期时间：`YYYYMMDD`（全天）、`YYYYMMDDTHHMMSS`（本地浮动）、
  /// `...Z`（UTC → 本地）。带 TZID 的按墙上时钟处理（不换算）。
  static ({DateTime date, bool allDay})? _parseDate(
    ({String value, Map<String, String> params})? prop,
  ) {
    final raw = prop?.value.trim() ?? '';
    if (raw.length < 8) return null;
    int n(int from, int len) =>
        int.tryParse(raw.substring(from, from + len)) ?? 0;
    final allDay = raw.length == 8;
    var d = DateTime(
      n(0, 4),
      n(4, 2),
      n(6, 2),
      allDay ? 0 : n(9, 2),
      allDay ? 0 : n(11, 2),
      allDay ? 0 : n(13, 2),
    );
    // 带 Z 的是 UTC，要换算到本机时区（本地浮动值原样用）
    if (raw.endsWith('Z')) {
      d = DateTime.utc(
        d.year,
        d.month,
        d.day,
        d.hour,
        d.minute,
        d.second,
      ).toLocal();
    }
    return (date: d, allDay: allDay);
  }

  static List<String> _unfold(String text) {
    final flat = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // 折行：换行后紧跟一个空格 / 制表符 → 接回去（RFC 5545 §3.1）
    final out = <String>[];
    for (final line in flat.split('\n')) {
      if (out.isNotEmpty && (line.startsWith(' ') || line.startsWith('\t'))) {
        out[out.length - 1] = out.last + line.substring(1);
      } else {
        out.add(line);
      }
    }
    return out;
  }

  /// `NAME;PARAM=V:值` → (NAME, 值, {PARAM: V})。冒号在引号里时不算分隔。
  static (String, String, Map<String, String>) _splitProperty(String line) {
    var quote = false;
    var colon = -1;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') quote = !quote;
      if (ch == ':' && !quote) {
        colon = i;
        break;
      }
    }
    if (colon < 0) return ('', '', const {});
    final head = line.substring(0, colon);
    final value = line.substring(colon + 1);
    final parts = head.split(';');
    final params = <String, String>{};
    for (final p in parts.skip(1)) {
      final i = p.indexOf('=');
      if (i > 0) params[p.substring(0, i).toUpperCase()] = p.substring(i + 1);
    }
    return (parts.first.toUpperCase(), value, params);
  }

  static String _unesc(String s) => s
      .replaceAll(RegExp(r'\\[nN]'), '\n')
      .replaceAll('\\,', ',')
      .replaceAll('\\;', ';')
      .replaceAll('\\\\', '\\');

  // ── 文本格式（RFC 5545 §3.1 / §3.3.11）──

  static String _esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\r\n', '\\n')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\n');

  /// 一行折成不超过 75 个八位组（续行以 CRLF + 一个空格开头）。按字符切，不切坏多字节。
  static String _fold(String line) {
    if (utf8.encode(line).length <= 75) return line;
    final out = StringBuffer();
    var count = 0;
    for (final rune in line.runes) {
      final ch = String.fromCharCode(rune);
      final size = utf8.encode(ch).length;
      if (count + size > (count == 0 ? 75 : 74)) {
        out.write('$_lineEnd ');
        count = 0;
      }
      out.write(ch);
      count += size;
    }
    return out.toString();
  }

  /// UTC 时间戳（DTSTAMP 按 RFC 必须是 UTC）。
  static String _utcStamp(DateTime t) {
    final u = t.toUtc();
    return '${u.year.toString().padLeft(4, '0')}${_pad2(u.month)}${_pad2(u.day)}'
        'T${_pad2(u.hour)}${_pad2(u.minute)}${_pad2(u.second)}Z';
  }

  static String _floating(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}${_pad2(t.month)}${_pad2(t.day)}'
      'T${_pad2(t.hour)}${_pad2(t.minute)}${_pad2(t.second)}';

  static String _dayStamp(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${_pad2(d.month)}${_pad2(d.day)}';

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  static String _hhmm(String slotStart) =>
      _minutes(slotStart).toString().padLeft(4, '0');

  /// 'HH:MM' → 当天分钟数；解析不出返回 -1。
  static int _minutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return -1;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return -1;
    return h * 60 + m;
  }
}

/// 导出的一条内容（一次课 / 一条日程）。
class TtOccurrence {
  const TtOccurrence({
    required this.uid,
    required this.title,
    required this.date,
    required this.startMin,
    required this.endMin,
    this.place = '',
    this.description = '',
    this.isEvent = false,
    this.rrule = '',
  });

  /// 稳定的 UID：同一次课每次导出都一样 → 重复导入到日历 App 不会翻倍。
  final String uid;
  final String title;
  final DateTime date;
  final int startMin;
  final int endMin;
  final String place;
  final String description;

  /// true = 来自日程（[TtEvent]），false = 来自课程。
  final bool isEvent;

  /// 重复日程的 RRULE（如 `FREQ=WEEKLY;INTERVAL=2`）；空 = 只发生这一次。
  final String rrule;

  String get timeText =>
      '${(startMin ~/ 60).toString().padLeft(2, '0')}:${(startMin % 60).toString().padLeft(2, '0')}'
      '-${(endMin ~/ 60).toString().padLeft(2, '0')}:${(endMin % 60).toString().padLeft(2, '0')}';
}

/// 导出范围。
enum IcsScope {
  day('今天'),
  week('本周'),
  month('本月'),
  semester('全学期');

  const IcsScope(this.label);
  final String label;

  /// 起止日期（含两端）。「本周」按自然周（周一起）；学期外没有课就是空的。
  (DateTime, DateTime) range(DateTime today, SemesterTt tt) {
    final t = DateTime(today.year, today.month, today.day);
    switch (this) {
      case IcsScope.day:
        return (t, t);
      case IcsScope.week:
        final mon = t.subtract(Duration(days: t.weekday - 1));
        return (mon, mon.add(const Duration(days: 6)));
      case IcsScope.month:
        return (DateTime(t.year, t.month, 1), DateTime(t.year, t.month + 1, 0));
      case IcsScope.semester:
        final start = DateTime.tryParse(tt.startDate);
        if (start == null || start.year <= 1970) {
          return (t, t); // 没设学期起点：退化成「今天」，由调用方提示
        }
        final s = DateTime(start.year, start.month, start.day);
        return (s, s.add(Duration(days: tt.weekCount.clamp(1, 40) * 7 - 1)));
    }
  }
}

/// 从 .ics 解析出来的一条事件（导入用）。
class IcsEvent {
  const IcsEvent({
    required this.summary,
    required this.date,
    required this.weekday,
    required this.startMin,
    required this.endMin,
    this.location = '',
    this.description = '',
    this.uid = '',
    this.allDay = false,
    this.simplified = false,
    this.repeat = 'weekly',
    this.repeatStart = '',
    this.repeatEnd = '',
  });

  final String summary;
  final String location;
  final String description;
  final String uid;

  /// 具体日期；**null = 重复日程**（按 [repeat] 与 [weekday]）。
  final DateTime? date;

  /// 0 = 周一（date 为 null 时表示每周几）。
  final int weekday;
  final int startMin;
  final int endMin;

  /// 全天事件（没有具体时刻，按 00:00-23:59 摆放）。
  final bool allDay;

  /// 原文件的重复规则我们不支持，只取了首次发生。
  final bool simplified;

  /// 重复类型（date 为 null 时有效）：weekly / biweekly / monthly。
  final String repeat;

  /// 重复的起始日期（原文件 DTSTART，`YYYY-MM-DD`）；空 = 没有起点。
  /// 每两周 / 每月要靠它定锚点（单双周、每月几号）。
  final String repeatStart;

  /// 重复的结束日期（`YYYY-MM-DD`）；空 = 没有期限。
  final String repeatEnd;
}
