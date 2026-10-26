import 'package:campus_core/campus_core.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归用例：16:30–18:00（晚饭空档）没有节次，日程不能因此从周视图里消失。
/// 典型场景：17:40–18:00 的临时事项。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();

    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 3));
    final (xnm, xqm) = AppState.inferSemester(now);
    TimetableStore.instance.semesters = {
      '$xnm-$xqm': SemesterTt(
        startDate: TimetableStore.iso(start),
        weekCount: 20,
        events: [
          TtEvent(
            id: 'e-gap',
            name: '晚饭空档日程',
            date: TimetableStore.iso(start.add(const Duration(days: 2))),
            start: '17:40',
            end: '18:00',
          ),
        ],
      ),
    };
    TimetableStore.instance.active = '$xnm-$xqm';
  });

  testWidgets('周视图能画出 17:40–18:00 的日程', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: TimetablePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('晚饭空档日程'), findsWidgets);
    expect(find.text('17:40~18:00'), findsOneWidget);
    // 周视图的日程块是 Positioned；日视图卡片不是。确保不是只靠日视图/近期日程兜住。
    expect(
      find.ancestor(
          of: find.text('晚饭空档日程'), matching: find.byType(Positioned)),
      findsWidgets,
    );
  });
}
