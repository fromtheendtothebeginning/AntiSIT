import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

// 拓展页（底栏页）的界面：三种加法、卡片图标与简介、添加菜单、总开关、内置项、删除。
void main() {
  setUpExtensionEnv();

  testWidgets('三种加法：填网址能加一条，网址不合法就不入列', (tester) async {
    await PluginRegistry.I.enable('ext');
    await pumpPage(tester);
    expect(find.text('还没有拓展'), findsOneWidget, reason: '没有内置拓展');

    await tester.tap(find.text('填写网址'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'example.com/tool');
    await tester.enterText(find.byType(TextField).at(2), '一句话简介');
    await tester.enterText(find.byType(TextField).at(3), '🛠');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(
      ExtensionStore.I.items.single.url,
      'https://example.com/tool',
      reason: '没写协议按 https 补',
    );
    expect(find.text('一句话简介'), findsOneWidget, reason: '简介显示在名称下方');
    expect(find.text('🛠'), findsOneWidget, reason: '自定义图标');

    // 网址不合法：报错、不入列
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('填写网址'));
    await tester.pumpAndSettle();
    await tester.enterText(dialogFields().at(0), '坏拓展');
    await tester.enterText(dialogFields().at(1), 'ftp://x.com');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.textContaining('网址要能打开'), findsOneWidget);
    expect(ExtensionStore.I.items, hasLength(1), reason: '没通过校验就不该加进去');
  });

  testWidgets('导入 JSON：数组 / 单条都收，坏 JSON 报错且不入列', (tester) async {
    await PluginRegistry.I.enable('ext');
    await pumpPage(tester);

    await tester.tap(find.text('导入 JSON'));
    await tester.pumpAndSettle();
    await tester.enterText(
      dialogFields(),
      '[{"name":"甲","url":"a.example.com"},{"url":"https://b.example.com"}]',
    );
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(ExtensionStore.I.items, hasLength(2));
    expect(find.text('甲'), findsWidgets, reason: '卡片上（徽章 + 标题）');
    expect(
      find.textContaining('b.example.com'),
      findsWidgets,
      reason: '缺名字用域名',
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入 JSON'));
    await tester.pumpAndSettle();
    await tester.enterText(dialogFields(), '{坏掉的');
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(ExtensionStore.I.items, hasLength(2), reason: '解析失败不该改动清单');
  });

  testWidgets('卡片图标跟工具宫格同一规格：24 图标 + 8 内边距，抓到站点图标就显示它', (tester) async {
    SiteIcon.loader = (_) async => fakePng(); // 别走网络
    await PluginRegistry.I.enable('ext');
    await ExtensionStore.I.add(
      const ExtensionItem(id: 'e1', name: '甲', url: 'https://a.example.com'),
    );
    await pumpPage(tester);

    final img = find.byType(Image);
    expect(img, findsOneWidget, reason: '用抓到的站点图标渲染（不是首字徽章）');
    expect(tester.getSize(img).width, 24, reason: '与工具宫格同一个 24');
    final pad = tester
        .widget<Container>(
          find.ancestor(of: img, matching: find.byType(Container)).first,
        )
        .padding;
    expect(pad, const EdgeInsets.all(8), reason: '与工具宫格同一个 8 内边距');
  });

  testWidgets('窄屏长简介不撑破卡片', (tester) async {
    // 回归：卡片高度曾按宽度算宽高比（1.16），360dp 屏上两行简介 + 网址会溢出圆角外
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await PluginRegistry.I.enable('ext');
    await ExtensionStore.I.add(
      const ExtensionItem(
        id: 'e1',
        name: '查空教室',
        url: 'https://a.example.com/tool',
        desc: '按教学楼和节次查当前空闲的教室，数据来自教务系统，支持上午下午晚上三段查询',
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: ExtensionsPage()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '简介 / 网址不能画出卡片外');
  });

  testWidgets('「添加拓展」还是原来的底部菜单；另有一项进独立市场页', (tester) async {
    await PluginRegistry.I.enable('ext');
    await pumpPage(tester);
    expect(find.text('还没有拓展'), findsOneWidget);

    // 右上角「添加拓展」圆钮 → 底部菜单（三种加法 + 市场入口）
    await tester.tap(find.byTooltip('添加拓展'));
    await tester.pumpAndSettle();
    // 底部菜单出现后，空态页上的同名按钮也在树里，所以用 findsWidgets
    expect(find.text('填写网址'), findsWidgets, reason: '三种加法照旧');
    expect(find.text('导入 JSON'), findsWidgets);
    expect(find.text('插件市场'), findsOneWidget, reason: '多了一项市场入口');

    // 点「插件市场」→ 独立的插件市场页
    await tester.tap(find.text('插件市场'));
    await tester.pumpAndSettle();
    expect(find.text('搜名称 / 简介 / 作者'), findsOneWidget, reason: '市场页有搜索框');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('还没有拓展'), findsOneWidget, reason: '回到拓展页');
  });

  testWidgets('总开关：一下隐藏全部网址，详情里仍能看全，再点一下恢复', (tester) async {
    await PluginRegistry.I.enable('ext');
    await ExtensionStore.I.add(
      const ExtensionItem(id: 'e1', name: '甲', url: 'https://a.example.com/x'),
    );
    await ExtensionStore.I.add(
      const ExtensionItem(id: 'e2', name: '乙', url: 'https://b.example.com/y'),
    );
    await pumpPage(tester);
    expect(find.textContaining('a.example.com'), findsOneWidget);
    expect(find.textContaining('b.example.com'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('example.com'),
      findsNothing,
      reason: '两张卡片的网址一起没了',
    );
    expect(find.text('网址已隐藏'), findsNothing, reason: '不留占位文字，那一行直接不显示');
    expect(ExtensionStore.I.hideUrls, isTrue);

    // 编辑 / 详情里照旧看得到（不然没法改）
    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    expect(find.textContaining('a.example.com'), findsWidgets);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('a.example.com'),
      findsOneWidget,
      reason: '关掉开关就恢复显示',
    );
  });

  testWidgets('内置拓展：带「内置」标记、没有删除入口、详情只读', (tester) async {
    ExtensionStore.builtins = const [
      ExtensionItem(
        id: 'b1',
        name: '内置甲',
        url: 'https://a.example.com',
        desc: '随包发布的固定网站',
        builtin: true,
      ),
    ];
    await PluginRegistry.I.enable('ext');
    await pumpPage(tester);

    expect(find.text('内置'), findsOneWidget, reason: '卡片上有标记');
    expect(find.text('随包发布的固定网站'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsNothing, reason: '内置的不给删');
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    expect(find.text('拓展详情'), findsOneWidget);
    expect(find.text('保存'), findsNothing, reason: '只读，没有保存');

    await ExtensionStore.I.remove('b1');
    expect(
      ExtensionStore.I.items.any((e) => e.id == 'b1'),
      isTrue,
      reason: 'store 层面也删不掉',
    );
  });

  testWidgets('卡片菜单能删掉一条', (tester) async {
    await PluginRegistry.I.enable('ext');
    await ExtensionStore.I.add(
      const ExtensionItem(id: 'e1', name: '甲', url: 'https://a.example.com'),
    );
    await pumpPage(tester);
    expect(find.text('甲'), findsWidgets);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(ExtensionStore.I.items, isEmpty);
    expect(find.text('甲'), findsNothing, reason: '卡片没了');
    expect(find.text('还没有拓展'), findsOneWidget, reason: '删空回到空态');
  });
}

