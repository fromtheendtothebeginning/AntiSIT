import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

// 拓展 → 内核的接口桥：配色 / 存储 / 主题推送 / card.set* / 内置项覆盖值。
void main() {
  setUpExtensionEnv();

  testWidgets('给拓展的接口：配色 / 存储 / 未知方法报错', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    final bridge = ExtBridge(
      extId: 'e1',
      context: tester.element(find.byType(SizedBox)),
      store: ExtensionStore.I,
    );

    final theme = await bridge.call('theme', null) as Map;
    expect(theme['isDark'], isFalse);
    expect(
      theme['accent'],
      matches(RegExp(r'^#[0-9a-f]{6}$')),
      reason: '配色给十六进制，拓展照着画',
    );
    expect(
      theme['menuBg'],
      matches(RegExp(r'^(#[0-9a-f]{6}|rgba\(.*\))$')),
      reason: '弹层底色等完整色板也要给',
    );
    expect(theme['inputFill'], isNotNull);
    expect(theme['radiusCard'], 16);
    expect(theme['wells'], isA<List>());

    SemColors.p = GlassPalette.dark;
    addTearDown(() => SemColors.p = GlassPalette.light);
    final dark = await bridge.call('theme', null) as Map;
    expect(dark['isDark'], isTrue);
    expect(
      dark['menuBg'],
      isNot(theme['menuBg']),
      reason: '夜间模式换的是整套色板，不只是 isDark',
    );

    await bridge.call('storage.set', {'key': 'a', 'value': 42});
    expect(await bridge.call('storage.get', {'key': 'a'}), 42);
    await bridge.call('storage.remove', {'key': 'a'});
    expect(await bridge.call('storage.get', {'key': 'a'}), isNull);

    await expectLater(bridge.call('没有这个接口', null), throwsArgumentError);
    await expectLater(
      bridge.call('storage.get', null),
      throwsArgumentError,
      reason: '参数不对要报错，不能静默失败',
    );
  });

  testWidgets('主题 / 夜间模式切换：完整色板推给网页，卸载后不再推', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    final bridge = ExtBridge(
      extId: 'e1',
      context: tester.element(find.byType(SizedBox)),
      store: ExtensionStore.I,
    );
    final sink = RecordingSink();
    bridge.attachEventSink(sink);
    addTearDown(() {
      bridge.attachEventSink(null);
      SemColors.p = GlassPalette.light;
    });

    SemColors.p = GlassPalette.dark;
    await tester.pump();
    final events = sink.events.where((e) => e.$1 == 'theme.change').toList();
    expect(events, hasLength(1));
    final data = events.single.$2 as Map;
    expect(data['isDark'], isTrue);
    expect(data['menuBg'], isNotNull);
    expect(data['onAccent'], isNotNull);
    expect(data['wells'], isA<List>());

    // 同一个色板对象不会造成重复推送
    SemColors.p = GlassPalette.dark;
    await tester.pump();
    expect(sink.events.where((e) => e.$1 == 'theme.change'), hasLength(1));

    // 页面关掉后不能再往一个已经没了的网页推
    bridge.attachEventSink(null);
    SemColors.p = GlassPalette.light;
    await tester.pump();
    expect(sink.events.where((e) => e.$1 == 'theme.change'), hasLength(1));
  });

  testWidgets('接口：card.setDesc 改自己卡片的简介（空串 = 不显示，落盘）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    final context = tester.element(find.byType(SizedBox));
    final bridge = ExtBridge(
      extId: 'e1',
      context: context,
      store: ExtensionStore.I,
    );
    await ExtensionStore.I.add(
      const ExtensionItem(
        id: 'e1',
        name: '甲',
        url: 'https://a.example.com',
        desc: '旧简介',
      ),
    );

    expect(
      await bridge.call('card.setDesc', {'text': ' 上次同步 3 条 '}),
      isTrue,
      reason: '两端空白会去掉',
    );
    expect(ExtensionStore.I.items.single.desc, '上次同步 3 条');

    await bridge.call('card.setDesc', {'text': ''});
    expect(
      ExtensionStore.I.items.single.desc,
      isEmpty,
      reason: '空串 = 卡片上不显示简介',
    );

    ExtensionStore.I = ExtensionStore(); // 模拟重启
    await ExtensionStore.I.load();
    expect(ExtensionStore.I.items.single.desc, isEmpty, reason: '简介落盘了');

    await expectLater(
      bridge.call('card.setDesc', null),
      throwsArgumentError,
      reason: '参数不对要报错',
    );
    await expectLater(
      bridge.call('card.setDesc', {
        'text': 'x' * (ExtensionItem.descMaxLength + 1),
      }),
      throwsArgumentError,
      reason: '超长直接报错，不静默截断',
    );
    await expectLater(
      ExtBridge(
        extId: '查无此条',
        context: context,
        store: ExtensionStore.I,
      ).call('card.setDesc', {'text': 'x'}),
      throwsArgumentError,
      reason: '改不了别人的 / 不在清单里的拓展',
    );
  });

  testWidgets('接口：card.setName / card.setIcon 也能改，校验各按各的上限', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    final context = tester.element(find.byType(SizedBox));
    final bridge = ExtBridge(
      extId: 'e1',
      context: context,
      store: ExtensionStore.I,
    );
    await ExtensionStore.I.add(
      const ExtensionItem(id: 'e1', name: '甲', url: 'https://a.example.com'),
    );

    await bridge.call('card.setName', {'text': '我的成绩单'});
    expect(ExtensionStore.I.items.single.name, '我的成绩单');
    expect(ExtensionStore.I.items.single.id, 'e1', reason: '改名称不改 id');

    await bridge.call('card.setIcon', {'text': '🛠'});
    expect(ExtensionStore.I.items.single.icon, '🛠');
    await bridge.call('card.setIcon', {'text': 'https://x.example.com/i.png'});
    expect(
      ExtensionStore.I.items.single.iconIsImage,
      isTrue,
      reason: '图片网址照旧按图片渲染',
    );
    await bridge.call('card.setIcon', {'text': 'line:flag'});
    expect(ExtensionStore.I.items.single.icon, 'line:flag', reason: '镂空图标名合法');
    await expectLater(
      bridge.call('card.setIcon', {'text': 'line:no-such'}),
      throwsArgumentError,
      reason: '图标名不认识要报错，不静默回退',
    );

    await expectLater(
      bridge.call('card.setName', {'text': '   '}),
      throwsArgumentError,
      reason: '名称不能空（否则卡片没标题）',
    );
    await expectLater(
      bridge.call('card.setName', {
        'text': 'x' * (ExtensionItem.nameMaxLength + 1),
      }),
      throwsArgumentError,
    );
    await expectLater(
      bridge.call('card.setIcon', {'text': '五个字图标'}),
      throwsArgumentError,
      reason: '文字图标超过 ${ExtensionItem.iconTextMaxLength} 个字要报错',
    );
    await expectLater(
      bridge.call('card.setIcon', {'text': ''}),
      completes,
      reason: '空串 = 回到网站 favicon / 首字，是合法的',
    );

    ExtensionStore.I = ExtensionStore(); // 模拟重启
    await ExtensionStore.I.load();
    expect(ExtensionStore.I.items.single.name, '我的成绩单', reason: '落盘了');
    expect(ExtensionStore.I.items.single.icon, isEmpty);
  });

  testWidgets('接口：内置拓展的卡片字段也能改（落在覆盖值里，源码清单不动）', (tester) async {
    ExtensionStore.builtins = const [
      ExtensionItem(
        id: 'b1',
        name: '内置甲',
        url: 'https://a.example.com',
        builtin: true,
      ),
    ];
    await ExtensionStore.I.load();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    final bridge = ExtBridge(
      extId: 'b1',
      context: tester.element(find.byType(SizedBox)),
      store: ExtensionStore.I,
    );

    await bridge.call('card.setDesc', {'text': '上次同步 3 条'});
    await bridge.call('card.setName', {'text': '内置甲（改过）'});
    expect(ExtensionStore.I.items.single.desc, '上次同步 3 条');
    expect(ExtensionStore.I.items.single.name, '内置甲（改过）');
    expect(ExtensionStore.builtins.single.name, '内置甲', reason: '源码清单里的定义不动');

    ExtensionStore.I = ExtensionStore(); // 模拟重启
    await ExtensionStore.I.load();
    expect(ExtensionStore.I.items.single.desc, '上次同步 3 条', reason: '覆盖值落盘了');

    // 用户端仍然改不了内置项本身
    await ExtensionStore.I.update(
      const ExtensionItem(
        id: 'b1',
        name: '用户改的',
        url: 'https://a.example.com',
        builtin: true,
      ),
    );
    expect(ExtensionStore.I.items.single.name, '内置甲（改过）', reason: '内置项不给用户改');
    await ExtensionStore.I.remove('b1');
    expect(ExtensionStore.I.items, hasLength(1), reason: '内置项不给用户删');
  });

  testWidgets('卡片跟着接口改：回列表就是新简介 / 名称 / 图标', (tester) async {
    await PluginRegistry.I.enable('ext');
    await ExtensionStore.I.add(
      const ExtensionItem(
        id: 'e1',
        name: '甲',
        url: 'https://a.example.com',
        desc: '旧简介',
      ),
    );
    await pumpPage(tester);
    expect(find.text('旧简介'), findsOneWidget);

    await ExtensionStore.I.setCard('e1', desc: '上次同步 3 条', name: '记账本');
    await tester.pumpAndSettle();

    expect(find.text('上次同步 3 条'), findsOneWidget);
    expect(find.text('旧简介'), findsNothing);
    expect(find.text('记账本'), findsOneWidget);

    await ExtensionStore.I.setCard('e1', icon: '🛠');
    await tester.pumpAndSettle();
    expect(find.text('🛠'), findsOneWidget, reason: '接口给的文字图标直接上卡片');
  });
}

