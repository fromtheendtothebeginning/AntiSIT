import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpExtensionEnv();

  group('限定 App 版本（minAppVersion）', () {
    test('导入的 JSON 也能声明，落盘回读', () async {
      final store = ExtensionStore.I;
      await store.load();
      await store.add(
        const ExtensionItem(
          id: 'e1',
          name: '甲',
          url: 'https://a.example.com',
          minAppVersion: '1.18.0',
        ),
      );

      ExtensionStore.I = ExtensionStore(); // 模拟重启
      await ExtensionStore.I.load();
      expect(ExtensionStore.I.items.single.minAppVersion, '1.18.0');
    });

    testWidgets('App 版本不够：卡片标「需升级 App」，点开提示升级且不进内核', (tester) async {
      final savedLoader = ExtensionItem.appVersionLoader;
      ExtensionItem.appVersionLoader = () async => '1.16.0';
      addTearDown(() => ExtensionItem.appVersionLoader = savedLoader);

      await PluginRegistry.I.enable('ext');
      await ExtensionStore.I.add(
        const ExtensionItem(
          id: 'e1',
          name: '未来拓展',
          url: 'https://a.example.com/tool',
          minAppVersion: '9.9.9',
        ),
      );
      await pumpPage(tester);
      expect(find.text('需升级 App'), findsOneWidget);

      await tester.tap(find.text('未来拓展'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('需要 App ≥9.9.9'),
        findsOneWidget,
        reason: '打开被拦下，说清原因（版本门在内核检查之前）',
      );
    });

    testWidgets('App 版本够：卡片没有标记，照常打开', (tester) async {
      final savedLoader = ExtensionItem.appVersionLoader;
      ExtensionItem.appVersionLoader = () async => '10.0.0';
      addTearDown(() => ExtensionItem.appVersionLoader = savedLoader);

      await PluginRegistry.I.enable('ext');
      await ExtensionStore.I.add(
        const ExtensionItem(
          id: 'e1',
          name: '未来拓展',
          url: 'https://a.example.com/tool',
          minAppVersion: '9.9.9',
        ),
      );
      await pumpPage(tester);
      expect(find.text('需升级 App'), findsNothing);

      await tester.tap(find.text('未来拓展'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('需要 App'),
        findsNothing,
        reason: '版本门放行（测试环境内核不可用，会走平台不支持那句）',
      );
    });
  });
}

