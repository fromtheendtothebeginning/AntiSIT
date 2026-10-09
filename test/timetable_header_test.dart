import 'package:campus_core/campus_core.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 需求：顶部「今天」卡与「近期日程」条**不随下方课表左右切换而横移**（它们与周次无关），
/// 但仍与课表在同一条竖向滚动里（整页一起上下滑，见 timetable_scroll_test）。
void main() {
  late String startISO;
  late int todayWeek;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();

    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1))
        .subtract(const Duration(days: 28));
    startISO = TimetableStore.iso(monday);
    todayWeek = TimetableStore.locateToday(startISO, 40)!;

    final (xnm, xqm) = AppState.inferSemester(DateTime.now());
    TimetableStore.instance.semesters = {
      '$xnm-$xqm': SemesterTt(
        startDate: startISO,
        weekCount: 40,
        // 每天 6 节：日视图里内容比「初始兜底高度」更高，才能验证页高量对了（否则末条会被裁）
        courses: [
          for (var d = 0; d < 7; d++)
            for (var s = 0; s < 6; s++)
              TtCourse(
                id: 'c-$d-$s',
                name: '课程${s + 1}',
                day: d,
                slotStart: s,
                slotEnd: s,
                weekType: 'all',
                weekStart: 1,
                weekEnd: 40,
                place: 'A10$s',
              ),
        ],
        events: [
          TtEvent(
              id: 'e1',
              name: '期中考试',
              date: TimetableStore.iso(now),
              start: '09:00',
              end: '11:00',
              kind: 'exam'),
        ],
      ),
    };
    TimetableStore.instance.active = '$xnm-$xqm';
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1900);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: TimetablePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  double cardX(WidgetTester tester) => tester.getTopLeft(find.textContaining('今天 · 第')).dx;

  /// 横滑一段（分两步：第一步被触摸 slop 吃掉，第二步才是真实位移）
  Future<TestGesture> dragBy(WidgetTester tester, double dx) async {
    final g = await tester.startGesture(tester.getCenter(find.byType(PageView)));
    await g.moveBy(Offset(dx / 3, 0));
    await tester.pump();
    await g.moveBy(Offset(dx * 2 / 3, 0));
    await tester.pump();
    return g;
  }

  testWidgets('周视图：横滑时顶部两块留在原地，只有课表格子在动', (tester) async {
    await pumpPage(tester);
    expect(find.text('近期日程'), findsOneWidget);

    final before = cardX(tester);
    final colBefore = tester.getTopLeft(find.text('周一').first).dx;

    final g = await dragBy(tester, -180);

    expect(cardX(tester), before, reason: '顶部卡不该跟着横向位移');
    expect(tester.getTopLeft(find.text('近期日程')).dx, before,
        reason: '近期日程条同样留在原地');
    expect(tester.getTopLeft(find.text('周一').first).dx, lessThan(colBefore - 50),
        reason: '课表格子要跟着手指走');

    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('切周后顶部两块内容不变（仍是今天的课，不是那一周的小结）', (tester) async {
    await pumpPage(tester);
    expect(find.textContaining('今天 · 第$todayWeek周'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.textContaining('今天 · 第$todayWeek周'), findsOneWidget,
        reason: '顶部卡说的是今天，与当前看的是哪一周无关');
    expect(find.textContaining('本周'), findsNothing, reason: '近期日程不按当前周打「本周」标');
    expect(find.textContaining('期中考试'), findsOneWidget, reason: '近期日程照常显示');
  });

  testWidgets('日视图：顶部两块留在原地，且当周最高的那天的内容不被裁', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byIcon(Icons.calendar_view_day_rounded));
    await tester.pumpAndSettle();

    // 日视图第 1 页 = 周一，6 节课都应渲染出来（页高量小了会把末条裁掉）
    expect(find.textContaining('今天 · 第'), findsOneWidget);
    final last = find.text('课程6');
    expect(last, findsWidgets);
    final pagerBottom = tester.getBottomLeft(find.byType(PageView)).dy;
    expect(tester.getBottomLeft(last.first).dy, lessThanOrEqualTo(pagerBottom + 0.5),
        reason: '最后一张卡要在分页可视范围内：日视图分页高度需要按当周最高的一天量');

    // 日视图里横滑同样不动顶部两块
    final before = cardX(tester);
    final g = await dragBy(tester, -180);
    expect(cardX(tester), before);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('调休补课当天：顶部卡照样显示今天的课（原来会一片空白）', (tester) async {
    final now = DateTime.now();
    // 补课天 = 今天按「今天+3 天」那天的课表上课（被借的星期一定与今天不同）
    final borrowed = (now.weekday - 1 + 3) % 7;
    final lastSlotEnd = DateTime(now.year, now.month, now.day, 19, 35); // 第 10 节下课时刻

    final (xnm, xqm) = AppState.inferSemester(now);
    TimetableStore.instance.semesters = {
      '$xnm-$xqm': SemesterTt(
        startDate: startISO,
        weekCount: 40,
        // 被借那天晚上有一门两节连上的课（保证「今天还没上完」可判定）
        courses: [
          TtCourse(
            id: 'borrowed',
            name: '补课',
            day: borrowed,
            slotStart: 8,
            slotEnd: 9,
            weekType: 'all',
            weekStart: 1,
            weekEnd: 40,
          ),
        ],
        adjustments: [
          TtAdjust(date: TimetableStore.iso(now), type: 'follow', day: borrowed),
        ],
      ),
    };
    TimetableStore.instance.active = '$xnm-$xqm';

    await pumpPage(tester);

    expect(find.textContaining('按周${'一二三四五六日'[borrowed]}上课'), findsOneWidget,
        reason: '卡片右侧要说明今天按哪天的课表上课');
    // 「最近一节课」那一行是卡片独有的（格子里只显示课名/地点，没有「第 N 节」这样的行）
    final nextRow = find.textContaining('第9-10节');
    if (now.isBefore(lastSlotEnd)) {
      // 关键回归：判「上完没有」若用被借那天的日期，这门课会被当成早就上完，卡片那一行就不见了
      expect(nextRow, findsOneWidget, reason: '调休补课当天卡片要显示今天最近的一节课');
      expect(find.text('补课'), findsWidgets);
    } else {
      expect(nextRow, findsNothing, reason: '补的课下课后照常从卡片上消失');
    }
  });
}
