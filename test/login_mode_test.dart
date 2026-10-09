import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 登录页要能让用户**自己选**接入方式：默认直连（学号 + 统一身份认证密码），
/// 也能切到服务器模式（服务器域名或 IP + 账号密码）。之前只有服务器账号登录一条路。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
  });

  testWidgets('默认停在直连模式：有学号与统一身份认证密码字段', (tester) async {
    AppState.I.serverUrl = ''; // 没配过服务器 → 首次选直连
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pump();

    expect(find.text('直连模式'), findsWidgets); // 选项卡
    expect(find.text('服务器模式'), findsWidgets);
    expect(find.text('学号'), findsOneWidget);
    // 「统一身份认证密码」在字段标签与说明里都出现，至少有一处（字段标签）
    expect(find.textContaining('统一身份认证密码'), findsWidgets);
    expect(find.text('直连并进入'), findsOneWidget);
    expect(find.text('用户名'), findsNothing, reason: '服务器字段不该同时出现');
  });

  testWidgets('切到服务器模式：要填服务器地址 + 账号密码', (tester) async {
    AppState.I.serverUrl = '';
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pump();

    await tester.tap(find.text('服务器模式').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('服务器地址'), findsWidgets);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('登 录'), findsOneWidget);
    expect(find.text('学号'), findsNothing, reason: '直连字段应让位');
  });

  testWidgets('已在用服务器模式的用户：默认停在服务器页', (tester) async {
    AppState.I.serverUrl = 'https://anticraft.top';
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pump();

    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('学号'), findsNothing);
  });

  testWidgets('服务器地址校验：空地址拦下，IP:端口 放行', (tester) async {
    AppState.I.serverUrl = 'https://anticraft.top';
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.tap(find.text('登 录'));
    await tester.pump();
    expect(find.text('请输入服务器域名或 IP'), findsOneWidget);

    // 归一化规则：IP/localhost 默认 http、域名默认 https
    expect(AppState.normalizeServer('192.168.1.10:8000'), 'http://192.168.1.10:8000');
    expect(AppState.normalizeServer('anticraft.top'), 'https://anticraft.top');
  });
}
