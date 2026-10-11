import 'package:campus_core/campus_core.dart';
import 'package:campus_service/pages/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 需求：「我的」页的「学籍信息」「服务状态」两张卡可以收起，默认展开。
/// （两张卡都不短，想只看头部提要时点一下标题就收掉。）
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    // 只要求「登录态」：这两张卡只在登录后出现。用服务器模式的 token（不走演示数据，
    // 免得演示模式那套模拟延时定时器在用例结束时还挂着）。
    AppState.I.mode = AppMode.server;
    AppState.I.token = 'test-token';
  });

  tearDown(() => AppState.I.token = null);

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 学籍信息的正文（没取到学籍时是那句「…后自动获取」的提示）。
  final infoBody = find.textContaining('自动获取');

  testWidgets('默认展开：两张卡的内容都在', (tester) async {
    await pumpPage(tester);
    expect(find.text('学籍信息'), findsOneWidget);
    expect(find.text('服务状态'), findsOneWidget);
    expect(infoBody, findsOneWidget);
    expect(find.text('学工登录'), findsOneWidget, reason: '服务状态的明细也在');
  });

  testWidgets('点标题收起，再点展开', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('学籍信息'));
    await tester.pumpAndSettle();
    expect(find.text('学籍信息'), findsOneWidget, reason: '标题留着');
    expect(infoBody, findsNothing, reason: '正文收起来了');

    await tester.tap(find.text('学籍信息'));
    await tester.pumpAndSettle();
    expect(infoBody, findsOneWidget);
  });

  testWidgets('两张卡各收各的：收服务状态不影响学籍信息', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('服务状态'));
    await tester.pumpAndSettle();
    expect(find.text('学工登录'), findsNothing);
    expect(find.text('服务状态'), findsOneWidget, reason: '标题留着');
    expect(infoBody, findsOneWidget, reason: '学籍信息不受影响');
  });
}
