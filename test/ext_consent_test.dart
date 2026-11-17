import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('能力文案由 App 生成', () {
    expect(ExtConsentService.title('clipboard.read'), '读取剪贴板');
    expect(ExtConsentService.title('net.host:mooc1.chaoxing.com'),
        '访问 mooc1.chaoxing.com');
    expect(ExtConsentService.body('测试拓展', 'clipboard.read'), contains('剪贴板'));
    expect(
        ExtConsentService.body('测试拓展', 'net.host:example.com'),
        contains('example.com'));
    expect(ExtConsentService.describe('net.host:example.com'),
        '访问 example.com');
  });

  test('已记住的授权不再弹框', () async {
    SharedPreferences.setMockInitialValues({
      'plugin.ext.consent.ext.a.net.host:example.com': true,
      'plugin.ext.consent.ext.a.clipboard.read': false,
    });
    final grants = await ExtConsentService.I.grants('ext.a');
    expect(grants['net.host:example.com'], isTrue);
    expect(grants['clipboard.read'], isFalse);

    // 没有 BuildContext 也能返回已记住的结果（不会走到弹框）
    final allowed = await ExtConsentService.I.ensure(
      _NoContext(),
      extId: 'ext.a',
      extName: '测试',
      capability: 'net.host:example.com',
    );
    expect(allowed, isTrue);
  });

  test('撤销全部', () async {
    SharedPreferences.setMockInitialValues({
      'plugin.ext.consent.ext.a.clipboard.read': true,
      'plugin.ext.consent.ext.b.clipboard.read': true,
    });
    await ExtConsentService.I.revokeAll('ext.a');
    expect(await ExtConsentService.I.grants('ext.a'), isEmpty);
    expect((await ExtConsentService.I.grants('ext.b')).length, 1);
  });

  test('权限管理界面直接允许 / 拒绝', () async {
    await ExtConsentService.I.allow('ext.a', 'notification.popup');
    expect((await ExtConsentService.I.grants('ext.a'))['notification.popup'],
        isTrue);
    await ExtConsentService.I.deny('ext.a', 'notification.popup');
    expect((await ExtConsentService.I.grants('ext.a'))['notification.popup'],
        isFalse);
    expect(ExtConsentService.describe('notification.popup'), '发送弹窗通知');
  });

  testWidgets('第一次弹框，允许后记住', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));

    final future = ExtConsentService.I.ensure(
      ctx,
      extId: 'ext.demo',
      extName: '演示拓展',
      capability: 'net.host:example.com',
    );
    await tester.pumpAndSettle();
    expect(find.text('访问 example.com'), findsOneWidget);
    expect(find.textContaining('演示拓展'), findsOneWidget);

    await tester.tap(find.text('允许'));
    await tester.pumpAndSettle();
    expect(await future, isTrue);

    final grants = await ExtConsentService.I.grants('ext.demo');
    expect(grants['net.host:example.com'], isTrue);
  });

  testWidgets('拒绝也会记住', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));

    final future = ExtConsentService.I.ensure(
      ctx,
      extId: 'ext.demo2',
      extName: '演示拓展',
      capability: 'clipboard.read',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('拒绝'));
    await tester.pumpAndSettle();
    expect(await future, isFalse);

    final grants = await ExtConsentService.I.grants('ext.demo2');
    expect(grants['clipboard.read'], isFalse);
  });
}

/// 只用来验证「已记住的授权不需要真的 BuildContext」。
class _NoContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('不应该用到 context');
}
