import 'package:campus_core/campus_core.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 需求：课表要「整页一起上下滑」——顶部「今天」卡与近期日程条跟着课程表一起滚，
/// 而不是只有课表格子滚、卡片钉在上面。
void main() {
  late String startISO;
  late int todayWeek;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();

    // 学期起点 = 本周一往前 4 周，保证「今天」落在学期内（第 5 周左右）
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1))
        .subtract(const Duration(days: 28));
    startISO = TimetableStore.iso(monday);
    todayWeek = TimetableStore.locateToday(startISO, 40)!;

    // 页面用 inferSemester(now) 推断当前学期，key 必须一致，否则页面读的是空学期
    final (xnm, xqm) = AppState.inferSemester(DateTime.now());
    TimetableStore.instance.semesters = {
      '$xnm-$xqm': SemesterTt(
        startDate: startISO,
        weekCount: 40,
        courses: [
          TtCourse(
            id: 'c1',
            name: '高数',
            day: DateTime.now().weekday - 1,
            slotStart: 0,
            slotEnd: 1,
            weekType: 'all',
            weekStart: 1,
            weekEnd: 40,
            place: 'A101',
          ),
        ],
      ),
    };
    TimetableStore.instance.active = '$xnm-$xqm';
  });

  testWidgets('上下滑动时，顶部「今天」卡跟着一起走（不是固定不动）', (tester) async {
    tester.view.physicalSize = const Size(1080, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: TimetablePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final card = find.textContaining('今天 · 第$todayWeek周');
    expect(card, findsOneWidget, reason: '顶部卡应已渲染（起于 $startISO，今天第 $todayWeek 周）');

    final before = tester.getTopLeft(card).dy;

    // 手指从下往上拖 = 内容上移
    await tester.drag(find.byType(TimetablePage), const Offset(0, -160));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final after = tester.getTopLeft(card).dy;
    expect(after, lessThan(before - 20),
        reason: '顶部卡应随滚动上移（before=$before after=$after）；若不动说明它仍是固定的');
  });
}
