import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_activities/plugin_activities.dart';
import 'package:plugin_score/plugin_score.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 工具二级页新增的两个视图：二课活动「我的报名」、二课分数「加分明细」，
/// 都与原视图左右滑动切换。用演示数据跑整页。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppState.I.demo = true;
  });
  tearDown(() => AppState.I.demo = false);

  testWidgets('二课活动：左右滑动切到「我的报名」，展示已报名活动', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ActivitiesPage()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('活动广场'), findsOneWidget);
    expect(find.text('我的报名'), findsOneWidget);

    // 左滑切到「我的报名」
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.text('AI 赋能学习效率提升讲座'), findsOneWidget);
    expect(find.text('秋季校园马拉松志愿者'), findsOneWidget);
    expect(find.text('已报名'), findsWidgets);
  });

  testWidgets('二课分数：点「加分明细」显示加分记录与累计学分', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ScorePage()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('分数概览'), findsOneWidget);

    await tester.tap(find.text('加分明细'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('加分记录'), findsOneWidget);
    expect(find.text('累计学分'), findsOneWidget);
    expect(find.text('AI 赋能学习效率提升讲座'), findsOneWidget);
    expect(find.text('秋季校园马拉松志愿者'), findsOneWidget);
    expect(find.textContaining('0.2 学分'), findsOneWidget);
    // 累计学分是 0.2+0.5+0.3：必须显示 1，而不是 1.0000000000000002
    expect(find.textContaining('0000000'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
