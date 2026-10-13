import 'package:campus_core/campus_core.dart';
import 'package:campus_service/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「导出 / 导入日历」（iCalendar，RFC 5545）的验收：
/// * 场次展开：周次区间、单双周、调休（放假 / 调课）都按课表页同一套判据；
/// * 导出范围：今天 / 本周 / 本月 / 全学期各收哪些日期；
/// * .ics 文本：必需属性、CRLF、TEXT 转义、75 八位组折行、浮动本地时刻；
/// * 解析：折行还原、转义还原、全天 / UTC / 本地三种时间、简单每周重复；
/// * 页面：范围切换与勾选会改变导出内容，全不选后不能导出。
void main() {
  // 2026-03-02 是周一：第 1 周周一，6 周 → 3/2 ~ 4/12
  const start = '2026-03-02';

  TtCourse course(String id, String name, int day, int s, int e,
          {String weekType = 'all', int w1 = 1, int w2 = 6}) =>
      TtCourse(
        id: id,
        name: name,
        day: day,
        slotStart: s,
        slotEnd: e,
        weekType: weekType,
        weekStart: w1,
        weekEnd: w2,
        place: '教一 101',
        teachers: '张老师',
      );

  SemesterTt semester({
    List<TtCourse> courses = const [],
    List<TtEvent> events = const [],
    List<TtAdjust> adjustments = const [],
    int weekCount = 6,
  }) =>
      SemesterTt(
        name: '2025-2026 第二学期',
        startDate: start,
        weekCount: weekCount,
        courses: [...courses],
        events: [...events],
        adjustments: [...adjustments],
      );

  /// 默认课表：周一高数（1-6 周）、周三英语（单周）、周六实验（双周）、
  /// 每周五例会 + 一条期中考试。
  SemesterTt sample({List<TtAdjust> adjustments = const []}) => semester(
        courses: [
          course('c1', '高等数学', 0, 0, 1),
          course('c2', '英语', 2, 4, 5, weekType: 'odd', w2: 5),
          course('c3', '实验', 5, 9, 10, weekType: 'even', w1: 2),
        ],
        events: [
          TtEvent(id: 'e1', name: '期中考试', date: '2026-03-12', day: 3, start: '10:00', end: '11:30', place: '教三 205', kind: 'exam'),
          TtEvent(id: 'e2', name: '组会', date: '', day: 4, start: '16:00', end: '17:00'),
        ],
        adjustments: adjustments,
      );

  List<TtOccurrence> expanded(SemesterTt tt, IcsScope scope, DateTime today) =>
      TimetableIcs.occurrences(
        tt: tt,
        courses: tt.courses,
        events: tt.events,
        scope: scope,
        slotStarts: TimetableStore.slotStarts,
        slotEnds: TimetableStore.slotEnds,
        today: today,
      );

  group('场次展开', () {
    test('不设学期起点就展不开（导出页面据此拦住）', () {
      final tt = semester(courses: [course('c1', '高数', 0, 0, 1)]);
      tt.startDate = '';
      expect(expanded(tt, IcsScope.semester, DateTime(2026, 3, 2)), isEmpty);
    });

    test('单双周与周次区间各按各的规则出现', () {
      final items = expanded(sample(), IcsScope.semester, DateTime(2026, 3, 2));
      final math = items.where((i) => i.title == '高等数学').toList();
      final english = items.where((i) => i.title == '英语').toList();
      final lab = items.where((i) => i.title == '实验').toList();
      expect(math, hasLength(6), reason: '1-6 周每周一都有');
      expect(english, hasLength(3), reason: '单周 1/3/5');
      expect(lab, hasLength(3), reason: '双周 2/4/6');
      expect(english.map((i) => i.date.day), [4, 18, 1], reason: '3/4、3/18、4/1');
    });

    test('时刻取自节次表，地点与变更清单进描述', () {
      final first = expanded(sample(), IcsScope.day, DateTime(2026, 3, 2)).single;
      expect(first.title, '高等数学');
      expect(first.startMin, 8 * 60 + 20);
      expect(first.endMin, 9 * 60 + 55);
      expect(first.place, '教一 101');
      expect(first.description, contains('第 1-2 节'));
      expect(first.timeText, '08:20-09:55');
    });

    test('范围：今天 / 本周 / 本月 / 全学期', () {
      final tt = sample();
      final today = DateTime(2026, 3, 2); // 周一
      expect(expanded(tt, IcsScope.day, today), hasLength(1));
      expect(expanded(tt, IcsScope.week, today), hasLength(3),
          reason: '本周 = 3/2~3/8：周一高数 + 周三英语 + 周五组会');
      expect(expanded(tt, IcsScope.month, today), hasLength(14),
          reason: '3/1~3/31：前 4 周 + 3/30（第 5 周周一）');
      expect(expanded(tt, IcsScope.semester, today), hasLength(19));
    });

    test('调休：放假当天没有课，调课当天上被调那天的课', () {
      final off = expanded(
          sample(adjustments: [TtAdjust(date: '2026-03-09', type: 'off')]),
          IcsScope.semester,
          DateTime(2026, 3, 2));
      expect(off.where((i) => i.title == '高等数学'), hasLength(5), reason: '3/9 放假，少一次');

      final follow = expanded(
          sample(adjustments: [TtAdjust(date: '2026-03-14', type: 'follow', day: 0)]),
          IcsScope.semester,
          DateTime(2026, 3, 2));
      final math = follow.where((i) => i.title == '高等数学').toList();
      expect(math, hasLength(7), reason: '6 个周一 + 3/14 调到周一');
      expect(math.map((i) => i.date.day), contains(14), reason: '3/14（周六）按周一上课');
    });

    test('定日期的日程按日期出现，放假也照常；每周日程跟着当天课表走', () {
      final tt = sample(adjustments: [TtAdjust(date: '2026-03-13', type: 'off')]);
      final items = expanded(tt, IcsScope.semester, DateTime(2026, 3, 2));
      expect(items.where((i) => i.title == '组会'), hasLength(5),
          reason: '3/13 放假，那天没有组会');
      expect(items.where((i) => i.title == '期中考试'), hasLength(1));
      expect(items.firstWhere((i) => i.title == '期中考试').date, DateTime(2026, 3, 12));
      expect(items.firstWhere((i) => i.title == '期中考试').isEvent, isTrue);
    });
  });

  group('导出 .ics', () {
    String build(SemesterTt tt, IcsScope scope, {DateTime? today}) => TimetableIcs.build(
          tt: tt,
          courses: tt.courses,
          events: tt.events,
          scope: scope,
          slotStarts: TimetableStore.slotStarts,
          slotEnds: TimetableStore.slotEnds,
          now: today ?? DateTime(2026, 3, 2, 12),
        );

    test('必需属性齐全，CRLF 换行，DTSTAMP 是 UTC，时刻是本地浮动', () {
      final text = build(sample(), IcsScope.day);
      final lines = text.split('\r\n');
      expect(text.contains('\r\n'), isTrue);
      expect(lines, contains('BEGIN:VCALENDAR'));
      expect(lines, contains('VERSION:2.0'));
      expect(lines.any((l) => l.startsWith('PRODID:')), isTrue);
      expect(lines.where((l) => l.startsWith('DTSTAMP:')).every((l) => l.endsWith('Z')), isTrue,
          reason: 'DTSTAMP 必须是 UTC');
      expect(lines, contains('DTSTART:20260302T082000'), reason: '本地浮动时刻，不带 Z');
      expect(lines, contains('DTEND:20260302T095500'));
      expect(lines, contains('SUMMARY:高等数学'));
      expect(lines, contains('LOCATION:教一 101'));
      expect(lines, contains('X-WR-TIMEZONE:Asia/Shanghai'));
      expect(text.trimRight().endsWith('END:VCALENDAR'), isTrue);
      expect(text.endsWith('\r\n'), isTrue);
    });

    test('UID 稳定：同一次课两次导出一致（重复导入不会翻倍）', () {
      String uidOf(String text) =>
          text.split('\r\n').firstWhere((l) => l.startsWith('UID:'));
      expect(uidOf(build(sample(), IcsScope.day)),
          uidOf(build(sample(), IcsScope.day, today: DateTime(2026, 3, 2, 20))));
    });

    test('TEXT 转义：逗号 / 分号 / 反斜杠 / 换行', () {
      final tt = semester(courses: [
        TtCourse(id: 'x', name: r'数学,分析;A\B', day: 0, slotStart: 0, slotEnd: 0,
            weekType: 'all', weekStart: 1, weekEnd: 1, place: '楼 3,401'),
      ], weekCount: 1);
      final text = build(tt, IcsScope.semester);
      expect(text, contains(r'SUMMARY:数学\,分析\;A\\B'));
      expect(text, contains(r'LOCATION:楼 3\,401'));
      expect(text, contains(r'DESCRIPTION:第 1 周'), reason: '描述里的换行用 \\n');
      expect(text.split('\r\n').any((l) => l.startsWith('DESCRIPTION:')), isTrue);
    });

    test('折行：每一物理行不超过 75 个八位组，还原后内容完整', () {
      final long = '超长课程名' * 20;
      final tt = semester(courses: [
        TtCourse(id: 'x', name: long, day: 0, slotStart: 0, slotEnd: 0,
            weekType: 'all', weekStart: 1, weekEnd: 1),
      ], weekCount: 1);
      final text = build(tt, IcsScope.semester);
      for (final line in text.split('\r\n')) {
        expect(line.codeUnits.length, lessThanOrEqualTo(75), reason: '物理行超长了：$line');
      }
      final summary = TimetableIcs.parse(text).single.summary;
      expect(summary, long, reason: '折行要能原样还原');
    });

    test('勾选决定内容：只勾课程就没有日程', () {
      final tt = sample();
      final withEvents = build(tt, IcsScope.semester);
      final coursesOnly = TimetableIcs.build(
        tt: tt,
        courses: tt.courses,
        events: const [],
        scope: IcsScope.semester,
        slotStarts: TimetableStore.slotStarts,
        slotEnds: TimetableStore.slotEnds,
        now: DateTime(2026, 3, 2),
      );
      expect(withEvents, contains('SUMMARY:期中考试'));
      expect(coursesOnly, isNot(contains('SUMMARY:期中考试')));
      expect(coursesOnly, isNot(contains('SUMMARY:组会')));
      expect(coursesOnly, contains('SUMMARY:高等数学'));
    });
  });

  group('解析 .ics', () {
    String wrap(String body) => [
          'BEGIN:VCALENDAR',
          'VERSION:2.0',
          'PRODID:-//test//CN',
          body,
          'END:VCALENDAR',
          '',
        ].join('\r\n');

    test('本地浮动时刻 + 地点 + 描述 + 折行还原', () {
      final events = TimetableIcs.parse(wrap([
        'BEGIN:VEVENT',
        'UID:abc@test',
        'SUMMARY:开题报告',
        'LOCATION:教二 301',
        'DTSTART:2026030',
        ' 3T140000',
        'DTEND:20260303T153000',
        'DESCRIPTION:第一行\\n第二行',
        'END:VEVENT',
      ].join('\r\n')));
      final e = events.single;
      expect(e.summary, '开题报告');
      expect(e.date, DateTime(2026, 3, 3));
      expect(e.startMin, 14 * 60);
      expect(e.endMin, 15 * 60 + 30);
      expect(e.location, '教二 301');
      expect(e.description, '第一行\n第二行');
      expect(e.weekday, 1, reason: '2026-03-03 是周二');
    });

    test('全天事件（VALUE=DATE）按 00:00-23:59 收下', () {
      final e = TimetableIcs.parse(wrap([
        'BEGIN:VEVENT',
        'SUMMARY:校运会',
        'DTSTART;VALUE=DATE:20260401',
        'END:VEVENT',
      ].join('\r\n'))).single;
      expect(e.allDay, isTrue);
      expect(e.date, DateTime(2026, 4, 1));
      expect(e.startMin, 0);
      expect(e.endMin, 1439);
    });

    test('UTC 时刻（Z）换算成本地', () {
      final e = TimetableIcs.parse(wrap([
        'BEGIN:VEVENT',
        'SUMMARY:视频会议',
        'DTSTART:20260303T060000Z',
        'DTEND:20260303T070000Z',
        'END:VEVENT',
      ].join('\r\n'))).single;
      final local = DateTime.utc(2026, 3, 3, 6).toLocal();
      expect(e.date, DateTime(local.year, local.month, local.day));
      expect(e.startMin, local.hour * 60 + local.minute, reason: '06:00Z → 本地 14:00');
    });

    test('每周重复：没有期限 → 收成本地「每周日程」', () {
      final e = TimetableIcs.parse(wrap([
        'BEGIN:VEVENT',
        'SUMMARY:组会',
        'DTSTART:20260306T160000',
        'DTEND:20260306T170000',
        'RRULE:FREQ=WEEKLY;BYDAY=FR',
        'END:VEVENT',
      ].join('\r\n'))).single;
      expect(e.date, isNull, reason: 'date 为空 = 每周重复');
      expect(e.weekday, 4);
      expect(e.startMin, 16 * 60);
    });

    test('每周重复带次数 → 逐条展开；复杂规则只取首次并标记', () {
      final counted = TimetableIcs.parse(wrap([
        'BEGIN:VEVENT',
        'SUMMARY:讲座',
        'DTSTART:20260304T190000',
        'RRULE:FREQ=WEEKLY;COUNT=3',
        'END:VEVENT',
      ].join('\r\n')));
      expect(counted, hasLength(3));
      expect(counted.map((e) => e.date!.day), [4, 11, 18]);

      final monthly = TimetableIcs.parse(wrap([
        'BEGIN:VEVENT',
        'SUMMARY:月度例会',
        'DTSTART:20260401T100000',
        'RRULE:FREQ=MONTHLY;BYMONTHDAY=1',
        'END:VEVENT',
      ].join('\r\n'))).single;
      expect(monthly.simplified, isTrue);
      expect(monthly.date, DateTime(2026, 4, 1));
    });

    test('坏输入不炸：没有 VEVENT / 只有噪声都得空列表', () {
      expect(TimetableIcs.parse('随便一段文字'), isEmpty);
      expect(TimetableIcs.parse(wrap('BEGIN:VEVENT\r\nSUMMARY:没有开始时间\r\nEND:VEVENT')),
          isEmpty);
    });

    test('导出的文件能原样读回来（往返）', () {
      final tt = sample();
      final text = TimetableIcs.build(
        tt: tt,
        courses: tt.courses,
        events: tt.events,
        scope: IcsScope.semester,
        slotStarts: TimetableStore.slotStarts,
        slotEnds: TimetableStore.slotEnds,
        now: DateTime(2026, 3, 2),
      );
      final back = TimetableIcs.parse(text);
      expect(back, hasLength(19));
      final math = back.where((e) => e.summary == '高等数学').toList();
      expect(math, hasLength(6));
      expect(math.first.startMin, 8 * 60 + 20);
      expect(math.first.location, '教一 101');
      expect(math.map((e) => e.date), contains(DateTime(2026, 3, 2)));
    });
  });

  group('导出 / 导入页', () {
    const key = '2025-12';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppState.I.load();
      TimetableStore.instance.semesters
        ..clear()
        ..[key] = sample();
      TimetableStore.instance.active = key;
    });

    tearDown(() {
      TimetableIcsPage.shareOverride = null;
      TimetableStore.instance.semesters.clear();
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(GlassPalette.light),
        home: const TimetableIcsPage(xnm: '2025', xqm: '12'),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('范围可切换，条数实时跟着变', (tester) async {
      await pump(tester);
      // 默认「本周」：页面上是真实今天，只断言四种范围里全学期的条数
      await tester.tap(find.text('全学期'));
      await tester.pumpAndSettle();
      expect(find.textContaining('将导出 19 条'), findsOneWidget);
      expect(find.textContaining('12 节课'), findsOneWidget, reason: '6+3+3 节课');
      expect(find.textContaining('7 条日程'), findsOneWidget, reason: '6 次组会 + 期中考试');
    });

    testWidgets('勾掉日程后不再导出日程（全不选）', (tester) async {
      await pump(tester);
      await tester.tap(find.text('全学期'));
      await tester.pumpAndSettle();
      // 日程卡里的「全不选」是第二个（课程卡里的是第一个）
      await tester.tap(find.text('全不选').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('将导出 12 条'), findsOneWidget);
      expect(find.textContaining('0 条日程'), findsOneWidget);
    });

    testWidgets('导出把选中内容交给分享（测试里换成假的）', (tester) async {
      String? shared;
      var files = 0;
      TimetableIcsPage.shareOverride = (text, name) async {
        shared = text;
        files++;
      };
      await pump(tester);
      await tester.tap(find.text('全学期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出并分享'));
      await tester.pumpAndSettle();
      expect(files, 1);
      expect(shared, contains('BEGIN:VCALENDAR'));
      expect(shared, contains('SUMMARY:高等数学'));
    });

    testWidgets('没设学期起点时：给提示且导出按钮不可用', (tester) async {
      TimetableStore.instance.semesters[key] = semester(courses: [], weekCount: 6)
        ..startDate = '';
      await pump(tester);
      expect(find.textContaining('尚未设置学期起点'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is FilledButton && w.onPressed == null),
          findsOneWidget, reason: '没有可导出的东西时按钮是灰的');
    });

    test('导入计划：超范围 / 重复的跳过，每周日程按星期几落下来', () {
      final plan = TimetableIcsPage.planImport([
        // 每周重复、学期内 → 收成「每周日程」
        const IcsEvent(summary: '讲座', date: null, weekday: 2, startMin: 600, endMin: 690),
        // 与已有日程重复（3/12 期中考试 10:00-11:30）→ 跳
        IcsEvent(
            summary: '期中考试',
            date: DateTime(2026, 3, 12),
            weekday: 3,
            startMin: 600,
            endMin: 690),
        // 超出学期范围 → 跳
        IcsEvent(
            summary: '夏令营',
            date: DateTime(2026, 7, 20),
            weekday: 0,
            startMin: 540,
            endMin: 600),
        // 复杂重复规则只取了首次 → 计入提示但照样导入
        IcsEvent(
            summary: '月度例会',
            date: DateTime(2026, 4, 1),
            weekday: 2,
            startMin: 600,
            endMin: 660,
            simplified: true),
      ], sample());

      expect(plan.items, hasLength(2), reason: '讲座 + 月度例会');
      expect(plan.items.first.date, '', reason: '每周重复的日程 date 留空');
      expect(plan.items.first.day, 2);
      expect(plan.items.first.start, '10:00');
      expect(plan.summary, contains('共 4 条事件'));
      expect(plan.summary, contains('将导入 2 条'));
      expect(plan.summary, contains('1 条不在本学期范围内'));
      expect(plan.summary, contains('1 条与已有日程重复'));
      expect(plan.summary, contains('1 条重复规则较复杂'));
    });
  });
}
