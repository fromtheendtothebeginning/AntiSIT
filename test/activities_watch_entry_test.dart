import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_activities/activity_watch_settings_page.dart';
import 'package:plugin_activities/plugin_activities.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 二课活动页顶栏的「新活动提醒」入口：点开就是提醒设置页，开关状态一眼可见。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // 单例不能换实例：直接把规则重置回默认（与 activity_watch_test 同一套做法）
    ActivityWatchService.I.rule = const ActivityWatchRule();
    ActivityWatchService.I.loaded = false;
    ActivityWatchService.I.lastError = null;
    await AppState.I.setDemo(true);
  });

  tearDown(() async => AppState.I.setDemo(false));

  testWidgets('顶栏铃铛：关着是描边，点开进提醒设置页', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ActivitiesPage()));
    await tester.pump(const Duration(milliseconds: 600));

    // 关着：描边铃铛
    expect(find.byIcon(Icons.notifications_none_outlined), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active), findsNothing);

    await tester.tap(find.byIcon(Icons.notifications_none_outlined));
    await tester.pumpAndSettle();
    expect(find.text('二课新活动提醒'), findsOneWidget, reason: '跳到了提醒设置页');
    expect(find.text('新活动提醒'), findsOneWidget);
  });

  testWidgets('开着提醒：铃铛变实心并高亮，返回后跟着变', (tester) async {
    ActivityWatchService.I.rule = const ActivityWatchRule(
      enabled: true,
      dl: {'思想成长'},
    );
    await tester.pumpWidget(const MaterialApp(home: ActivitiesPage()));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byIcon(Icons.notifications_active), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none_outlined), findsNothing);

    // 设置页里关掉开关，返回活动页时铃铛应当回到描边
    await tester.tap(find.byIcon(Icons.notifications_active));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新活动提醒'));
    await tester.pumpAndSettle();
    expect(ActivityWatchService.I.enabled, isFalse);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notifications_none_outlined), findsOneWidget);
  });
}