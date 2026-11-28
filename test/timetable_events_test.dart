import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_core/campus_core.dart';
import 'package:plugin_timetable/plugin_timetable.dart';

/// 日程的重复规则：显式 repeat 字段 + occursOn，以及老数据（date 空 = 每周）的兼容。
void main() {
  // 2026-03-02 是周一
  final semesterStart = DateTime(2026, 3, 2);

  TtEvent event(
    String repeat, {
    String date = '',
    int day = 0,
    String repeatStart = '',
    String repeatEnd = '',
    String start = '19:00',
  }) => TtEvent(
    id: 'e',
    name: '组会',
    date: date,
    day: day,
    start: start,
    end: '20:00',
    repeat: repeat,
    repeatStart: repeatStart,
    repeatEnd: repeatEnd,
  );

  group('老数据兼容', () {
    test('没有 repeat 字段：date 空算每周，有日期算单次', () {
      final weekly = TtEvent.fromJson({
        'id': 'a',
        'name': '组会',
        'date': '',
        'day': 4,
      });
      expect(weekly.repeat, TtEvent.repeatWeekly);
      expect(weekly.isRepeating, isTrue);

      final once = TtEvent.fromJson({
        'id': 'b',
        'name': '考试',
        'date': '2026-03-12',
      });
      expect(once.repeat, TtEvent.repeatNone);
      expect(once.isRepeating, isFalse);
    });

    test('toJson 写回 repeat / repeatStart / repeatEnd，读回来一致', () {
      final e = event(
        TtEvent.repeatBiweekly,
        day: 2,
        repeatStart: '2026-03-02',
        repeatEnd: '2026-06-01',
      );
      final back = TtEvent.fromJson(e.toJson());
      expect(back.repeat, TtEvent.repeatBiweekly);
      expect(back.repeatStart, '2026-03-02');
      expect(back.repeatEnd, '2026-06-01');
      expect(back.isRepeating, isTrue);
    });
  });

  group('occursOn', () {
    test('单次只在那一天发生', () {
      final e = event(TtEvent.repeatNone, date: '2026-03-12');
      expect(
        e.occursOn(DateTime(2026, 3, 12), semesterStart: semesterStart),
        isTrue,
      );
      expect(
        e.occursOn(DateTime(2026, 3, 13), semesterStart: semesterStart),
        isFalse,
      );
    });

    test('每周按星期几发生（有学期起点当锚点时 function 正常）', () {
      final e = event(TtEvent.repeatWeekly, day: 4); // 周五
      expect(
        e.occursOn(DateTime(2026, 3, 6), semesterStart: semesterStart),
        isTrue,
      );
      expect(
        e.occursOn(DateTime(2026, 3, 13), semesterStart: semesterStart),
        isTrue,
      );
      expect(
        e.occursOn(DateTime(2026, 3, 5), semesterStart: semesterStart),
        isFalse,
      );
    });

    test('每两周从 repeatStart 那一周起算，隔周一次', () {
      final e = event(
        TtEvent.repeatBiweekly,
        day: 4,
        repeatStart: '2026-03-02',
      );
      expect(
        e.occursOn(DateTime(2026, 3, 6), semesterStart: semesterStart),
        isTrue,
      );
      expect(
        e.occursOn(DateTime(2026, 3, 13), semesterStart: semesterStart),
        isFalse,
      );
      expect(
        e.occursOn(DateTime(2026, 3, 20), semesterStart: semesterStart),
        isTrue,
      );
    });

    test('起止日期是闭区间', () {
      final e = event(
        TtEvent.repeatWeekly,
        day: 4,
        repeatStart: '2026-03-06',
        repeatEnd: '2026-03-20',
      );
      expect(
        e.occursOn(DateTime(2026, 2, 27), semesterStart: semesterStart),
        isFalse,
      );
      expect(
        e.occursOn(DateTime(2026, 3, 6), semesterStart: semesterStart),
        isTrue,
      );
      expect(
        e.occursOn(DateTime(2026, 3, 20), semesterStart: semesterStart),
        isTrue,
      );
      expect(
        e.occursOn(DateTime(2026, 3, 27), semesterStart: semesterStart),
        isFalse,
      );
    });

    test('每月按 repeatStart 的几号发生；当月没有这一天时取月末', () {
      final e = event(TtEvent.repeatMonthly, repeatStart: '2026-01-31');
      expect(
        e.occursOn(DateTime(2026, 1, 31), semesterStart: semesterStart),
        isTrue,
      );
      expect(
        e.occursOn(DateTime(2026, 2, 28), semesterStart: semesterStart),
        isTrue,
      );
      expect(
        e.occursOn(DateTime(2026, 3, 31), semesterStart: semesterStart),
        isTrue,
      );
      expect(
        e.occursOn(DateTime(2026, 3, 30), semesterStart: semesterStart),
        isFalse,
      );
    });
  });

  group('nextOccurrence', () {
    test('复现的下一次：单次 / 每周 / 每两周 / 每月', () {
      expect(
        event(
          TtEvent.repeatNone,
          date: '2026-03-12',
        ).nextOccurrence(DateTime(2026, 3, 10), semesterStart: semesterStart),
        DateTime(2026, 3, 12),
      );
      expect(
        event(
          TtEvent.repeatWeekly,
          day: 4,
        ).nextOccurrence(DateTime(2026, 3, 10), semesterStart: semesterStart),
        DateTime(2026, 3, 13),
      );
      expect(
        event(
          TtEvent.repeatBiweekly,
          day: 4,
          repeatStart: '2026-03-02',
        ).nextOccurrence(DateTime(2026, 3, 10), semesterStart: semesterStart),
        DateTime(2026, 3, 20),
      );
      expect(
        event(
          TtEvent.repeatMonthly,
          repeatStart: '2026-01-31',
        ).nextOccurrence(DateTime(2026, 3, 1), semesterStart: semesterStart),
        DateTime(2026, 3, 31),
      );
    });
  });

  group('筛选条件（EventFilter）', () {
    final tt = SemesterTt(
      startDate: '2026-03-02',
      weekCount: 16,
      events: [
        TtEvent(
          id: 'once',
          name: '期中考试',
          date: '2026-03-12',
          day: 3,
          start: '10:00',
          end: '11:30',
          repeat: TtEvent.repeatNone,
        ),
        TtEvent(
          id: 'weekly',
          name: '组会',
          date: '',
          day: 4,
          start: '16:00',
          end: '17:00',
          repeat: TtEvent.repeatWeekly,
        ),
        TtEvent(
          id: 'biweekly',
          name: '双周讲座',
          date: '',
          day: 2,
          start: '18:00',
          end: '19:00',
          repeat: TtEvent.repeatBiweekly,
          repeatStart: '2026-03-02',
        ),
        TtEvent(
          id: 'monthly',
          name: '月度例会',
          date: '',
          day: 0,
          start: '20:00',
          end: '21:00',
          repeat: TtEvent.repeatMonthly,
          repeatStart: '2026-03-04',
        ),
      ],
    );

    test('不选条件 = 全放行', () {
      expect(
        filterEvents(tt, filter: const EventFilter()).length,
        tt.events.length,
      );
      expect(filterEvents(tt).length, tt.events.length);
    });

    test('重复类型多选（同类 OR）', () {
      final weeklyOrBiweekly = const EventFilter(
        repeats: {TtEvent.repeatWeekly, TtEvent.repeatBiweekly},
      );
      final hit = filterEvents(tt, filter: weeklyOrBiweekly);
      expect(hit.map((e) => e.id), ['weekly', 'biweekly']);
    });

    test('时间段：开始不早于 + 结束不晚于（AND）', () {
      const f = EventFilter(startFrom: '16:00', startTo: '19:00');
      final hit = filterEvents(tt, filter: f);
      expect(hit.map((e) => e.id), ['weekly', 'biweekly']);
    });

    test('日期范围：只看区间里会发生的（重复日程也算下一次）', () {
      const f = EventFilter(dateFrom: '2026-03-09', dateTo: '2026-03-15');
      final hit = filterEvents(tt, filter: f);
      // 3/12 考试、3/13 组会在这周；双周讲座从 3/2 那周起算，3/11 落在单周不出。
      expect(hit.map((e) => e.id), ['once', 'weekly']);
      expect(
        hit.any((e) => e.id == 'monthly'),
        isFalse,
        reason: '3/4 之后下一次在 4/4',
      );

      // 下一周（3/16~3/22）轮到双周讲座
      const next = EventFilter(dateFrom: '2026-03-16', dateTo: '2026-03-22');
      expect(filterEvents(tt, filter: next).map((e) => e.id), [
        'weekly',
        'biweekly',
      ]);
    });

    test('多类条件同时生效：重复类型 + 时间段 + 日期范围', () {
      const f = EventFilter(
        repeats: {TtEvent.repeatWeekly},
        startFrom: '15:00',
        dateFrom: '2026-03-01',
        dateTo: '2026-03-31',
      );
      expect(filterEvents(tt, filter: f).map((e) => e.id), ['weekly']);
    });

    test('条件摘要写清已选的每一类', () {
      const f = EventFilter(
        startFrom: '16:00',
        repeats: {TtEvent.repeatMonthly},
        dateFrom: '2026-03-01',
        dateTo: '2026-03-31',
      );
      expect(f.summary, '16:00–不限 · 每月 · 03/01~03/31');
      expect(const EventFilter().summary, isEmpty);
    });
  });

  group('表单与筛选面板（界面）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TimetableStore.instance.semesters = {};
      TimetableStore.instance.active = '';
    });

    Future<void> pumpTimetable(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: TimetablePage()));
      await tester.pumpAndSettle();
    }

    Future<void> openMenu(WidgetTester tester, String item) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets('添加日程：分段是「单次 / 重复」，切到重复后出现重复类型与起止日期', (tester) async {
      await pumpTimetable(tester);
      await openMenu(tester, '添加日程');

      expect(find.text('单次'), findsOneWidget);
      expect(find.text('重复'), findsOneWidget);
      expect(find.text('每周'), findsNothing, reason: '选「单次」时不显示重复类型');

      await tester.tap(find.text('重复'));
      await tester.pumpAndSettle();
      expect(find.text('每两周'), findsOneWidget);
      expect(find.text('每月'), findsOneWidget);
      // 起止日期现在是玻璃选择器：「开始」显示学期起点，「结束」空着就是不限
      expect(find.text('开始'), findsOneWidget, reason: '循环开始是个日期选择器');
      expect(find.text('结束'), findsOneWidget, reason: '循环结束是个日期选择器');
      expect(find.text('不限（排到学期末）'), findsOneWidget, reason: '结束默认不限');

      await tester.tap(find.text('每两周'));
      await tester.pumpAndSettle();
      expect(find.text('星期'), findsOneWidget);
    });

    testWidgets('重复日程创建后按重复规则显示（每周出现两次）', (tester) async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 2));
      final (xnm, xqm) = AppState.inferSemester(now);
      TimetableStore.instance.semesters = {
        '$xnm-$xqm': SemesterTt(
          startDate: TimetableStore.iso(start),
          weekCount: 20,
          events: [
            TtEvent(
              id: 'w1',
              name: '每周例会',
              date: '',
              day: now.weekday - 1,
              start: '20:00',
              end: '21:00',
              repeat: TtEvent.repeatWeekly,
            ),
          ],
        ),
      };
      TimetableStore.instance.active = '$xnm-$xqm';
      await pumpTimetable(tester);
      expect(find.text('每周例会'), findsWidgets, reason: '每周重复的日程要画在网格里');
    });

    testWidgets('筛选面板：按重复类型筛掉后，顶栏出现「筛选生效中」，点一下清掉', (tester) async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 2));
      final (xnm, xqm) = AppState.inferSemester(now);
      TimetableStore.instance.semesters = {
        '$xnm-$xqm': SemesterTt(
          startDate: TimetableStore.iso(start),
          weekCount: 20,
          events: [
            TtEvent(
              id: 'w1',
              name: '每周例会',
              date: '',
              day: now.weekday - 1,
              start: '20:00',
              end: '21:00',
              repeat: TtEvent.repeatWeekly,
            ),
            TtEvent(
              id: 'o1',
              name: '一次性讲座',
              date: TimetableStore.iso(now),
              day: now.weekday - 1,
              start: '18:00',
              end: '19:00',
            ),
          ],
        ),
      };
      TimetableStore.instance.active = '$xnm-$xqm';
      await pumpTimetable(tester);

      await openMenu(tester, '筛选日程');
      expect(find.text('筛选日程'), findsWidgets);
      await tester.tap(find.widgetWithText(FilterChip, '每周'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('应用'));
      await tester.pumpAndSettle();

      expect(find.textContaining('筛选生效中'), findsOneWidget);
      expect(find.text('一次性讲座'), findsNothing, reason: '单次日程被筛掉了');

      await tester.tap(find.textContaining('筛选生效中'));
      await tester.pumpAndSettle();
      expect(find.textContaining('筛选生效中'), findsNothing);
      expect(find.text('一次性讲座'), findsWidgets);
    });
  });
}
