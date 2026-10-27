import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归用例：同一节次范围内的前后两条日程（09:00–09:30 / 09:30–10:00）
/// 原来都会被吸附到第 2 节整行，两张卡完全叠在一起。
/// 现在按真实分钟定位，前一条的底边必须落在后一条顶边之上。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    AppState.I.dimCompleted = false;

    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 3));
    final day = start.add(const Duration(days: 2));
    final (xnm, xqm) = AppState.inferSemester(now);
    final iso = TimetableStore.iso(day);
    TimetableStore.instance.semesters = {
      '$xnm-$xqm': SemesterTt(
        startDate: TimetableStore.iso(start),
        weekCount: 20,
        events: [
          TtEvent(id: 'e1', name: '第一节日程', date: iso, start: '09:00', end: '09:30'),
          TtEvent(id: 'e2', name: '第二节日程', date: iso, start: '09:30', end: '10:00'),
        ],
      ),
    };
    TimetableStore.instance.active = '$xnm-$xqm';
  });

  testWidgets('窄屏：前后相接的两条日程不再叠在一起', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: TimetablePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('第一节日程'), findsWidgets);
    expect(find.text('第二节日程'), findsWidgets);

    Rect cardOf(String name) => tester.getRect(
        find
            .ancestor(
                of: find.text(name), matching: find.byType(GestureDetector))
            .first);

    final first = cardOf('第一节日程');
    final second = cardOf('第二节日程');
    expect(first.bottom, lessThanOrEqualTo(second.top + 1));
    expect(tester.takeException(), isNull);
  });
}
