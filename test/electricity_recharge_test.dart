import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_electricity/plugin_electricity.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 电费充值的两条资金相关回归：
/// 1. 充值成功后**必须刷新余额**——否则页面停在前一秒的旧余额，用户以为没到账再充一次；
/// 2. 金额输入 `NaN` 必须被挡住——`num.tryParse('NaN')` 不是 null，且 NaN 与任何数
///    比较都为 false，旧校验 `amount < 0.01 || amount > 500` 会放它过去。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.I.demo = true;
    AppState.I.autoRefreshTools = false; // 只测手动这条路径，不额外打请求
    DemoData.eleBalance = 23.45;
  });

  tearDown(() {
    AppState.I.demo = false;
    AppState.I.autoRefreshTools = true;
  });

  testWidgets('充值成功后余额立即刷新（不能停在旧余额）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ElectricityPage()));
    // 首屏：等演示接口 400ms
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('¥23.45'), findsOneWidget);

    // 充值 10 元
    await tester.tap(find.widgetWithText(FilledButton, '充值'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '10');
    await tester.tap(find.widgetWithText(FilledButton, '确认充值'));
    await tester.pumpAndSettle();

    // 成功 + 刷新（query 又是一次 400ms 演示延迟）
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('¥33.45'), findsOneWidget,
        reason: '充值成功后必须重新查询余额，否则用户会以为没到账而重复充值');
    expect(find.text('¥23.45'), findsNothing);
  });

  testWidgets('金额输入 NaN 被校验挡下，不发充值请求', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ElectricityPage()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '充值'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'NaN');
    await tester.tap(find.widgetWithText(FilledButton, '确认充值'));
    await tester.pumpAndSettle();

    expect(find.text('金额须在 0.01 - 500 元之间'), findsOneWidget);
    expect(DemoData.eleBalance, 23.45, reason: 'NaN 绝不能进扣款接口');
    expect(find.text('✓ 充值成功'), findsNothing);
  });
}
