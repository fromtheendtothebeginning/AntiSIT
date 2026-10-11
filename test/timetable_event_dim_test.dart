import 'package:campus_core/campus_core.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 日程时间结束后也要淡下去（和周视图里「已上完的课」同一套：0.55 透明度）。
/// 判定按**结束时刻**，所以上周/昨天的日程在别处看也是灰的。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    AppState.I.dimCompleted = true; // 「上完的课淡化」开关默认开

    // 学期起点放三天前 → 今天落在第 1 周中间：这样「三天前」和「三天后」都在同一周里，
    // 无论测试什么时候跑，一个必定已结束、一个必定还没到（都在课表格子的时间范围内）。
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 3));
    final (xnm, xqm) = AppState.inferSemester(now);
    TimetableStore.instance.semesters = {
      '$xnm-$xqm': SemesterTt(
        startDate: TimetableStore.iso(start),
        weekCount: 20,
        events: [
          TtEvent(
            id: 'e-past',
            name: '已结束的日程',
            date: TimetableStore.iso(start), // 三天前 08:20~09:55，早就过去了
            start: '08:20',
            end: '09:55',
            place: '二教101',
          ),
          TtEvent(
            id: 'e-future',
            name: '还没到的日程',
            date: TimetableStore.iso(start.add(const Duration(days: 6))), // 三天后
            start: '13:00',
            end: '14:35',
            place: '二教102',
          ),
        ],
      ),
    };
    TimetableStore.instance.active = '$xnm-$xqm';
  });

  Future<void> pumpWeek(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: TimetablePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('周视图里：已结束的日程压暗，还没到的正常', (tester) async {
    await pumpWeek(tester);

    double opacitiyOf(String name) {
      final fade = tester.widget<Opacity>(
          find.ancestor(of: find.text(name), matching: find.byType(Opacity)).first);
      return fade.opacity;
    }

    expect(find.text('已结束的日程'), findsWidgets);
    expect(find.text('还没到的日程'), findsWidgets);
    expect(opacitiyOf('已结束的日程'), lessThan(0.6), reason: '结束时间过了 → 和周视图的课一样压暗');
    expect(opacitiyOf('还没到的日程'), 1.0, reason: '还没到 → 正常显示');
  });

  testWidgets('关掉「上完的课淡化显示」后，日程也按正常显示', (tester) async {
    AppState.I.dimCompleted = false;
    await pumpWeek(tester);
    final fade = tester.widget<Opacity>(find
        .ancestor(of: find.text('已结束的日程'), matching: find.byType(Opacity))
        .first);
    expect(fade.opacity, 1.0);
  });
}
