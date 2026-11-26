import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpExtensionEnv();

  group('市场装的拓展（版本 / 来源 / 权限）', () {
    final installed = ExtensionItem(
      id: 'sit.demo-counter',
      name: '记一笔',
      url: '/data/ext/sit.demo-counter/main.js',
      desc: '数数小工具',
      bundled: true,
      runtime: ExtensionItem.runtimeCordis,
      version: '1.0.0',
      sha256: 'a' * 64,
      permissions: ['storage'],
      fromMarket: true,
    );

    test('市场字段落盘后读得回（重启后还知道自己是市场装的、装的是哪版）', () async {
      final store = ExtensionStore.I;
      await store.load();
      await store.add(installed);

      ExtensionStore.I = ExtensionStore();
      await ExtensionStore.I.load();
      final back = ExtensionStore.I.items.single;
      expect(back.version, '1.0.0');
      expect(back.sha256, 'a' * 64);
      expect(back.permissions, ['storage']);
      expect(back.fromMarket, isTrue);
      expect(back.urlLine, '插件市场 · Cordis · v1.0.0', reason: '卡片上写清来源与版本');
    });

    test('老版本落盘数据（没这些字段）照旧读得回，且不被当成市场装的', () {
      final old = ExtensionItem.parse(
        jsonDecode('{"id":"e1","name":"甲","url":"https://a.example.com"}'),
      );
      expect(old.version, isEmpty);
      expect(old.permissions, isEmpty);
      expect(old.fromMarket, isFalse, reason: '来源是你自己填的 → 接口照旧全量');
      expect(old.urlLine, 'https://a.example.com');
    });

    test('在 App 里改名 / 接口改卡片，都不该把市场字段弄丢', () async {
      final store = ExtensionStore.I;
      await store.load();
      await store.add(installed);

      await store.update(
        store.items.single.copyWith(name: '我改的名字', desc: '改过的简介'),
      );
      await store.setCard('sit.demo-counter', icon: '🧮');

      final after = store.items.single;
      expect(after.name, '我改的名字');
      expect(after.version, '1.0.0');
      expect(after.sha256, 'a' * 64);
      expect(after.permissions, ['storage'], reason: '权限声明丢了 = 权限门失效');
      expect(after.fromMarket, isTrue);
    });

    test('删除拓展把它的键值数据一起清掉（删除弹窗就是这么承诺的）', () async {
      final store = ExtensionStore.I;
      await store.load();
      await store.add(installed);
      await store.dataSet(installed.id, 'count', 7);
      await store.dataSet('sit.other', 'count', 9);

      await store.remove(installed.id);
      expect(await store.dataGet(installed.id, 'count'), isNull);
      expect(await store.dataGet('sit.other', 'count'), 9, reason: '别的拓展不受影响');
      expect(store.items, isEmpty);
    });
  });
}

