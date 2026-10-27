import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归用例：窄屏 + 只有 1 节课高的课程卡，不能因为时间/课名/地点/教师
/// 叠在一起而溢出。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    AppState.I.dimCompleted = true;

    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 3));
    final day = start.add(const Duration(days: 2));
    final (xnm, xqm) = AppState.inferSemester(now);
    TimetableStore.instance.semesters = {
      '$xnm-$xqm': SemesterTt(
        startDate: TimetableStore.iso(start),
        weekCount: 20,
        courses: [
          TtCourse(
            id: 'c-small',
            name: '高等数学（一）与工程应用基础',
            place: '第二教学楼 A301 多媒体教室',
            teachers: '张老师、李老师',
            day: day.weekday - 1,
            slotStart: 0,
            slotEnd: 0,
            weekType: 'all',
            weekStart: 1,
            weekEnd: 20,
          ),
        ],
        events: [
          TtEvent(
            id: 'e-small',
            name: '临时班会与学生座谈交流安排',
            date: TimetableStore.iso(day),
            start: '08:20',
            end: '09:05',
            place: '第二教学楼 A301 多媒体教室',
            seat: '12',
          ),
        ],
      ),
    };
    TimetableStore.instance.active = '$xnm-$xqm';
  });

  testWidgets('窄屏 1 节课程卡不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: TimetablePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('高等数学（一）与工程应用基础'), findsWidgets);
    expect(find.text('临时班会与学生座谈交流安排'), findsWidgets);
    // 一节课高的卡片也要露教室号（地点拆成「楼名 + 编号」，编号单独一行）
    expect(find.text('A301'), findsWidgets);
    // 卡片内容按像素预算取舍，不能再有 RenderFlex 溢出（文字叠在一起）
    expect(tester.takeException(), isNull);
  });
}
