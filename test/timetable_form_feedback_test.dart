import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归用例：日程 / 课程表单的校验提示原来走 SnackBar，挂在页面 Scaffold 上，
/// 底部弹层一开就被盖住。现在提示画在弹层里，并且是红色。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    AppState.I.dimCompleted = false;
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

  /// 红色提示必须画在弹层里，而不是页面底部的 SnackBar。
  void expectRedHintInSheet(WidgetTester tester, String text) {
    expect(find.text(text), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing, reason: 'SnackBar 会被底部弹层盖住');
    expect(
        find.ancestor(of: find.text(text), matching: find.byType(BottomSheet)),
        findsOneWidget,
        reason: '提示要跟着表单一起显示在弹层内');
    expect(tester.widget<Text>(find.text(text)).style?.color, SemColors.danger,
        reason: '校验提示要是红色');
  }

  testWidgets('添加日程：只填名称不选日期，红色提示在弹层里可见', (tester) async {
    await pumpTimetable(tester);
    await openMenu(tester, '添加日程');

    await tester.enterText(find.byType(TextField).first, '交材料');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expectRedHintInSheet(tester, '单次日程需要选择日期');
  });

  testWidgets('添加课程：课程名为空，红色提示在弹层里可见', (tester) async {
    await pumpTimetable(tester);
    await openMenu(tester, '添加课程');

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expectRedHintInSheet(tester, '请填写课程名');
  });
}
