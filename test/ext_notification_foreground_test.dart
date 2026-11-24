import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 拓展通知的「前台横幅」与「授权不落假拒绝」这两条规则。
///
/// 背景：Android 会压掉应用自己在前台时发的横幅通知，于是「退到后台能收到、
/// 正开着 App 什么都看不到」。修法分两半——前台走页内横幅，后台照旧走系统通知；
/// 另外授权框问不到用户（页面已关 / 在后台）时不能当成「拒绝」存下来。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ExtForegroundNotice.I.debugReset();
  });

  /// 每个用例结尾都要把还挂着的横幅收掉：横幅自带「到点自动收起」的定时器，
  /// 不清掉会触发「A Timer is still pending」断言。
  void bannerTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      await body(tester);
      ExtForegroundNotice.I.dismissAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  }

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: SizedBox()),
    ));
    await tester.pump();
  }

  group('前台横幅', () {
    bannerTest('前台能弹，标题 / 正文 / 来源都在，点一下收起', (tester) async {
      await pumpHost(tester);

      final shown = ExtForegroundNotice.I.show(
        extId: 'sit.demo',
        title: '还有 3 小时：第三章作业',
        body: '截止今天 23:59',
        source: '学习通截止提醒',
      );
      expect(shown, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('还有 3 小时：第三章作业'), findsOneWidget);
      expect(find.text('截止今天 23:59'), findsOneWidget);
      expect(find.text('学习通截止提醒'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('还有 3 小时：第三章作业'), findsNothing);
    });

    bannerTest('同一条（同 key）覆盖，不叠两条', (tester) async {
      await pumpHost(tester);

      ExtForegroundNotice.I.show(extId: 'sit.demo', title: '第一条', key: 'k1');
      await tester.pump();
      ExtForegroundNotice.I.show(
          extId: 'sit.demo', title: '改过的标题', key: 'k1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('第一条'), findsNothing);
      expect(find.text('改过的标题'), findsOneWidget);
    });

    bannerTest('到点自动收起', (tester) async {
      await pumpHost(tester);
      ExtForegroundNotice.I.show(
        extId: 'sit.demo',
        title: '会自己消失',
        duration: const Duration(milliseconds: 300),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('会自己消失'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('会自己消失'), findsNothing);
    });

    bannerTest('同时最多挂 3 条，最早的先撤', (tester) async {
      await pumpHost(tester);
      for (final title in ['A', 'B', 'C', 'D']) {
        ExtForegroundNotice.I.show(extId: 'sit.demo', title: title);
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('A'), findsNothing, reason: '超过 3 条时最早的先撤');
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('D'), findsOneWidget);
    });

    bannerTest('退到后台自动收掉（后台交给系统通知）', (tester) async {
      await pumpHost(tester);
      ExtForegroundNotice.I.show(extId: 'sit.demo', title: '后台就不该留着');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('后台就不该留着'), findsOneWidget);

      // 走 inactive：resumed → paused 是非法跳转，测试框架会拦掉
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('后台就不该留着'), findsNothing);
      expect(ExtForegroundNotice.I.inForeground, isFalse);
      // 巡检 / 后续 show 都以这个为准：后台不弹页内横幅，交给系统通知

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(ExtForegroundNotice.I.inForeground, isTrue);
    });
  });

  group('运行时授权：问不到用户不算拒绝', () {
    testWidgets('在后台问不到 → 不落盘，下次还能再问', (tester) async {
      // 挂着页面（有全局 navigator），但 App 在后台：框弹出来也没人看得见
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        home: const SizedBox(),
      ));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      final allowed = await ExtConsentService.I.ensure(
        navKey.currentContext!,
        extId: 'ext.bg',
        extName: '后台拓展',
        capability: 'notification.popup',
      );
      expect(allowed, isFalse, reason: '这次调用按「没同意」处理');
      expect(
        (await ExtConsentService.I.grants('ext.bg'))['notification.popup'],
        isNull,
        reason: '关键：不能把「问不到」存成用户拒绝，否则永远恢复不了',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    });

    testWidgets('页面已关（context 失效）也不落盘', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      // 没有挂全局 navigator：navKey.currentContext 为 null
      final allowed = await ExtConsentService.I.ensure(
        _DeadContext(),
        extId: 'ext.gone',
        extName: '已关页面',
        capability: 'clipboard.read',
      );
      expect(allowed, isFalse);
      expect(await ExtConsentService.I.grants('ext.gone'), isEmpty);
    });

    testWidgets('真的点了拒绝才记住', (tester) async {
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        home: Builder(builder: (c) => const SizedBox()),
      ));
      final future = ExtConsentService.I.ensure(
        navKey.currentContext!,
        extId: 'ext.real',
        extName: '真拒绝',
        capability: 'notification.popup',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('拒绝'));
      await tester.pumpAndSettle();
      expect(await future, isFalse);
      expect(
        (await ExtConsentService.I.grants('ext.real'))['notification.popup'],
        isFalse,
        reason: '用户亲手点的拒绝要记住，下次别再弹',
      );
    });
  });

  group('旧版本留下的假拒绝要清掉', () {
    test('升级后把 false 清空，true 与其它键不受影响', () async {
      SharedPreferences.setMockInitialValues({
        'plugin.ext.consent.ext.a.notification.popup': false, // 旧的假拒绝
        'plugin.ext.consent.ext.a.clipboard.read': true,
        'plugin.ext.data.ext.a.k': 'v',
      });

      await ExtConsentService.migrateLegacyDenials();

      final grants = await ExtConsentService.I.grants('ext.a');
      expect(grants['notification.popup'], isNull, reason: '假拒绝已清，下次重新问');
      expect(grants['clipboard.read'], isTrue, reason: '真同意不能动');
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('plugin.ext.data.ext.a.k'), 'v');
    });

    test('只跑一次：之后用户新点的拒绝不会被再次清掉', () async {
      SharedPreferences.setMockInitialValues({});
      await ExtConsentService.migrateLegacyDenials();

      await ExtConsentService.I.deny('ext.b', 'notification.popup');
      await ExtConsentService.migrateLegacyDenials();

      expect(
        (await ExtConsentService.I.grants('ext.b'))['notification.popup'],
        isFalse,
        reason: '迁移是一次性的，别把用户后来的选择也洗掉',
      );
    });
  });
}

/// 失效的 context：任何使用都算错。
class _DeadContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('不应该用到 context');
}
