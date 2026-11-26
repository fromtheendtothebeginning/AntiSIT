import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

// 拓展的清单与存储层：默认开启与硬依赖、网址行、id 生成、镂空图标、总开关、本地持久化。
void main() {
  setUpExtensionEnv();

  test('默认开启 + 硬依赖内核：装好即可用，停用内核连带停掉拓展', () async {
    expect(PluginRegistry.I.isEnabled('ext'), isTrue, reason: '默认开启，底栏直接有「拓展」');
    expect(
      PluginRegistry.I.isEnabled(PluginIds.webview),
      isTrue,
      reason: '内核跟着一起开',
    );
    expect(
      PluginRegistry.I.capability<WebViewCapability>(PluginIds.webview),
      isNotNull,
    );

    final labels = [
      for (final (_, item) in PluginRegistry.I.navPages(ValueNotifier(0)))
        item.label,
    ];
    expect(labels, contains('拓展'), reason: '底栏名称就叫「拓展」');

    final off = await PluginRegistry.I.disable(PluginIds.webview);
    expect(off, contains('ext'), reason: '停用内核要把拓展一起停掉');
    expect(PluginRegistry.I.isEnabled('ext'), isFalse);
  });

  test('网址行：远程给完整网址，本地包说明来源', () {
    const remote = ExtensionItem(
      id: 'r',
      name: 'r',
      url: 'https://a.example.com/path/x',
    );
    expect(remote.urlLine, 'https://a.example.com/path/x');

    const bundled = ExtensionItem(
      id: 'b',
      name: 'b',
      url: '/data/ext/b/main.js',
      bundled: true,
      runtime: ExtensionItem.runtimeCordis,
    );
    expect(bundled.urlLine, '本地 Cordis 拓展');
  });

  test('批量生成的 id 不撞：数组导入在同一个微秒里也不能重键', () {
    final ids = {for (var i = 0; i < 500; i++) ExtensionItem.newId()};
    expect(ids.length, 500);
  });

  test('镂空图标：line:<name> 映射到 Material Outlined，未知名字回退', () {
    expect(ExtIcon.lineIcon('line:flag'), Icons.flag_outlined);
    expect(ExtIcon.lineIcon('line:handyman'), Icons.handyman_outlined);
    expect(ExtIcon.lineIcon('line:no-such'), Icons.extension_outlined);
    expect(ExtIcon.lineIcon('🔢'), isNull);
  });

  test('总开关状态落在本地：换个实例 load 还能读回来', () async {
    final store = ExtensionStore.I;
    await store.load();
    expect(store.hideUrls, isFalse, reason: '默认显示网址');

    await store.setHideUrls(true);

    ExtensionStore.I = ExtensionStore(); // 模拟重启
    await ExtensionStore.I.load();
    expect(ExtensionStore.I.hideUrls, isTrue);
  });

  test('清单与拓展存储落在本地：换个实例 load 还能读回来，且按拓展隔离', () async {
    final store = ExtensionStore.I;
    await store.load();
    await store.add(
      const ExtensionItem(
        id: 'x1',
        name: 'X',
        url: 'https://x.example.com',
        desc: '带简介',
      ),
    );
    await store.dataSet('x1', 'k', {'n': 1});

    ExtensionStore.I = ExtensionStore(); // 模拟重启
    await ExtensionStore.I.load();
    expect(ExtensionStore.I.items.single.name, 'X');
    expect(ExtensionStore.I.items.single.desc, '带简介', reason: '简介也存得住');
    expect(await ExtensionStore.I.dataGet('x1', 'k'), {'n': 1});
    expect(
      await ExtensionStore.I.dataGet('别的拓展', 'k'),
      isNull,
      reason: '存储按拓展 id 隔离',
    );
  });
}

