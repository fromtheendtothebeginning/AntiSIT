import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:plugin_webview/plugin_webview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「拓展」（底栏页，默认关闭、硬依赖 WebView 内核）的验收：
/// * 默认关闭；启用它会连带启用内核，停用内核会连带停掉它（关系图实线的语义）；
/// * 页面初始为空，三种加法：填网址 / 导入压缩包 / 导入 JSON；
/// * 压缩包：解压 + 入口识别 + css/js 内联成自包含页面 + zip-slip 防护；
/// * 卡片：favicon 默认图标 / 自定义 emoji 或图片 / 简介 / 网址（标题栏总开关可一下全隐藏）；
/// * 内置拓展（编译前固定）：带标记、不给删改，详情只读；
/// * 存储：清单与每个拓展的键值数据落在本地且按 id 隔离；
/// * 接口：配色 / 存储 / 简介（`card.setDesc` 改自己卡片的简介）与错误回传。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ExtensionStore.I = ExtensionStore();
    ExtensionStore.builtins = const [];
    SiteIcon.loader = SiteIcon.forPage;
    SiteIcon.clearCache();
    PluginRegistry.I = PluginRegistry(
      features: const [WebViewPlugin(), ExtPlugin()],
      themes: const [GlassTheme()],
      capabilities: const {PluginIds.webview: WebViewCapabilityImpl()},
    );
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ExtensionsPage()));
    await tester.pumpAndSettle();
  }

  /// 现造一个 zip（压缩包导入的测试用）。
  List<int> makeZip(Map<String, String> files) {
    final archive = Archive();
    files.forEach((name, content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    return ZipEncoder().encode(archive);
  }

  /// 造一个「只有一帧、那一帧是 PNG」的 ICO。
  Uint8List icoWithFrame(Uint8List frame) {
    final out = BytesBuilder()
      ..add(const [0, 0, 1, 0, 1, 0]) // ICONDIR：1 帧
      ..add(const [32, 32, 0, 0, 1, 0, 32, 0]); // 宽 32 高 32、32bpp
    final size = frame.length;
    final offset = 6 + 16;
    out
      ..add([size & 0xff, (size >> 8) & 0xff, (size >> 16) & 0xff, (size >> 24) & 0xff])
      ..add([
        offset & 0xff, (offset >> 8) & 0xff, (offset >> 16) & 0xff, (offset >> 24) & 0xff
      ])
      ..add(frame);
    return out.takeBytes();
  }

  /// 1×1 的透明 PNG（真的能解码，用来验渲染）。
  Uint8List fakePng() => base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

  test('默认关闭 + 硬依赖内核：启用连带打开内核，停用内核连带停掉拓展', () async {
    expect(PluginRegistry.I.isEnabled('ext'), isFalse, reason: '默认关闭，先不占底栏');

    final on = await PluginRegistry.I.enable('ext');
    expect(on, containsAll(<String>['ext', 'webview']), reason: '启用拓展要连带启用内核');
    expect(PluginRegistry.I.capability<WebViewCapability>(PluginIds.webview), isNotNull);

    final labels = [
      for (final (_, item) in PluginRegistry.I.navPages(ValueNotifier(0))) item.label,
    ];
    expect(labels, contains('拓展'), reason: '底栏名称就叫「拓展」');

    final off = await PluginRegistry.I.disable(PluginIds.webview);
    expect(off, contains('ext'), reason: '停用内核要把拓展一起停掉');
    expect(PluginRegistry.I.isEnabled('ext'), isFalse);
  });

  test('网址行：远程给完整网址，本地包说明来源', () {
    const remote = ExtensionItem(id: 'r', name: 'r', url: 'https://a.example.com/path/x');
    expect(remote.urlLine, 'https://a.example.com/path/x');

    const bundled = ExtensionItem(id: 'b', name: 'b', url: '/data/ext/b/index.html', bundled: true);
    expect(bundled.urlLine, '本地导入的压缩包');
  });

  group('网站图标', () {
    test('.ico 里嵌的 PNG 帧能抠出来（Flutter 自己解不了 .ico，这是没显示出来的原因）', () {
      final png = fakePng();
      final ico = icoWithFrame(png);
      expect(SiteIcon.isIco(ico), isTrue);
      expect(SiteIcon.pngFrameOfIco(ico), png, reason: '抠出那一帧 PNG');

      expect(SiteIcon.isIco(png), isFalse);
      expect(SiteIcon.pngFrameOfIco(png), isNull);
      expect(SiteIcon.pngFrameOfIco(icoWithFrame(Uint8List.fromList(const [0x28, 0, 0, 0]))),
          isNull, reason: '老式 DIB 帧不硬解，退回首字徽章');
    });

    test('候选地址：apple-touch-icon 优先、相对地址按页面解析、跳过 svg、站点根兜底', () {
      const origin = 'https://a.example.com';
      final page = Uri.parse('$origin/app/index.html');
      final urls = SiteIcon.iconCandidates(
          html: '<link rel="apple-touch-icon" href="/touch.png">'
              '<link rel="icon" type="image/svg+xml" href="/a.svg">'
              '<link rel="icon" href="favicon.png">'
              '<link rel="shortcut icon" href="/fav.ico">',
          page: page,
          origin: origin);
      final all = urls.map((u) => u.toString()).toList();
      expect(all.first, '$origin/touch.png', reason: 'apple-touch-icon 最清楚，排最前');
      expect(all, contains('$origin/app/favicon.png'), reason: '相对地址按页面地址解析');
      expect(all.any((u) => u.endsWith('.svg')), isFalse, reason: 'Flutter 不认 svg，跳过');
      expect(all.last, '$origin/favicon.ico', reason: '站点根兜底');
      expect(SiteIcon.iconCandidates(page: page, origin: origin).single.toString(),
          '$origin/favicon.ico', reason: '页面抓不到也要有兜底');
    });
  });

  group('压缩包导入', () {
    test('解开 html/js/css 三件套：入口找得到，css/js 内联成自包含页面', () {
      final dir = Directory.systemTemp.createTempSync('ext_test_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final zip = makeZip({
        'myapp/index.html':
            '<link rel="stylesheet" href="a.css"><h1>hi</h1><script src="b.js"></script>',
        'myapp/a.css': 'body{color:red}',
        'myapp/b.js': 'console.log("x")',
      });

      final bundle = extractBundle(bytes: zip, dir: dir.path);
      expect(bundle.entry, endsWith('myapp/index.html'),
          reason: '顶层目录只去掉一层：入口还是 myapp/index.html');
      final sib = File(bundle.entry).parent.path;
      expect(File('$sib/a.css').existsSync(), isTrue, reason: '都解出来了');

      final html = bundlePageHtml(bundle.entry);
      expect(html, contains('body{color:red}'), reason: '同目录的 css 内联进去了');
      expect(html, contains('console.log("x")'), reason: 'js 内联进去了');
      expect(html, isNot(contains('href="a.css"')), reason: '外链已经换成内联');
    });

    test('入口规则：优先 index.html，其次排序第一个 html；没有 html 就报错', () {
      expect(entryFileOf(['a.css', 'z.html', 'index.html']), 'index.html');
      expect(entryFileOf(['x/b.html', 'x/a.html']), 'x/a.html');
      expect(entryFileOf(['readme.txt', 'app/logo.png']), isNull);

      final dir = Directory.systemTemp.createTempSync('ext_test_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      expect(() => extractBundle(bytes: makeZip({'readme.txt': 'hi'}), dir: dir.path),
          throwsA(isA<FormatException>()));
    });

    test('zip-slip：绝对路径 / .. 的条目整条丢掉，绝不写到目标目录外面', () {
      expect(normalizeEntryPath('/etc/passwd'), isNull);
      expect(normalizeEntryPath('../evil.txt'), isNull);
      expect(normalizeEntryPath('a/../../b.txt'), isNull);
      expect(normalizeEntryPath(r'C:\Windows\x.dll'), isNull);
      expect(normalizeEntryPath('./app/index.html'), 'app/index.html');

      final dir = Directory.systemTemp.createTempSync('ext_test_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final bundle = extractBundle(
          bytes: makeZip({'index.html': '<h1>ok</h1>', '../evil.txt': 'bad'}),
          dir: dir.path);
      expect(File('${dir.parent.path}/evil.txt').existsSync(), isFalse,
          reason: '没写到目标目录外面');
      expect(File(bundle.entry).existsSync(), isTrue);
    });
  });

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

    expect(ExtensionStore.I.items.single.url, 'https://example.com/tool',
        reason: '没写协议按 https 补');
    expect(find.text('一句话简介'), findsOneWidget, reason: '简介显示在名称下方');
    expect(find.text('🛠'), findsOneWidget, reason: '自定义图标');

    // 网址不合法：报错、不入列
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('填写网址'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '坏拓展');
    await tester.enterText(find.byType(TextField).at(1), 'ftp://x.com');
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
    await tester.enterText(find.byType(TextField),
        '[{"name":"甲","url":"a.example.com"},{"url":"https://b.example.com"}]');
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(ExtensionStore.I.items, hasLength(2));
    expect(find.text('甲'), findsWidgets, reason: '卡片上（徽章 + 标题）');
    expect(find.textContaining('b.example.com'), findsWidgets, reason: '缺名字用域名');

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入 JSON'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '{坏掉的');
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(ExtensionStore.I.items, hasLength(2), reason: '解析失败不该改动清单');
  });

  testWidgets('卡片图标跟工具宫格同一规格：24 图标 + 8 内边距，抓到站点图标就显示它', (tester) async {
    SiteIcon.loader = (_) async => fakePng(); // 别走网络
    await PluginRegistry.I.enable('ext');
    await ExtensionStore.I.add(
        const ExtensionItem(id: 'e1', name: '甲', url: 'https://a.example.com'));
    await pumpPage(tester);

    final img = find.byType(Image);
    expect(img, findsOneWidget, reason: '用抓到的站点图标渲染（不是首字徽章）');
    expect(tester.getSize(img).width, 24, reason: '与工具宫格同一个 24');
    final pad = tester
        .widget<Container>(find.ancestor(of: img, matching: find.byType(Container)).first)
        .padding;
    expect(pad, const EdgeInsets.all(8), reason: '与工具宫格同一个 8 内边距');
  });

  testWidgets('总开关：一下隐藏全部网址，详情里仍能看全，再点一下恢复', (tester) async {
    await PluginRegistry.I.enable('ext');
    await ExtensionStore.I.add(const ExtensionItem(
        id: 'e1', name: '甲', url: 'https://a.example.com/x'));
    await ExtensionStore.I.add(const ExtensionItem(
        id: 'e2', name: '乙', url: 'https://b.example.com/y'));
    await pumpPage(tester);
    expect(find.textContaining('a.example.com'), findsOneWidget);
    expect(find.textContaining('b.example.com'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(find.textContaining('example.com'), findsNothing, reason: '两张卡片的网址一起没了');
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
    expect(find.textContaining('a.example.com'), findsOneWidget, reason: '关掉开关就恢复显示');
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

  testWidgets('内置拓展：带「内置」标记、没有删除入口、详情只读', (tester) async {
    ExtensionStore.builtins = const [
      ExtensionItem(
          id: 'b1',
          name: '内置甲',
          url: 'https://a.example.com',
          desc: '随包发布的固定网站',
          builtin: true),
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
    expect(ExtensionStore.I.items.any((e) => e.id == 'b1'), isTrue,
        reason: 'store 层面也删不掉');
  });

  testWidgets('卡片菜单能删掉一条', (tester) async {
    await PluginRegistry.I.enable('ext');
    await ExtensionStore.I.add(
        const ExtensionItem(id: 'e1', name: '甲', url: 'https://a.example.com'));
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

  test('清单与拓展存储落在本地：换个实例 load 还能读回来，且按拓展隔离', () async {
    final store = ExtensionStore.I;
    await store.load();
    await store.add(const ExtensionItem(
        id: 'x1', name: 'X', url: 'https://x.example.com', desc: '带简介'));
    await store.dataSet('x1', 'k', {'n': 1});

    ExtensionStore.I = ExtensionStore(); // 模拟重启
    await ExtensionStore.I.load();
    expect(ExtensionStore.I.items.single.name, 'X');
    expect(ExtensionStore.I.items.single.desc, '带简介', reason: '简介也存得住');
    expect(await ExtensionStore.I.dataGet('x1', 'k'), {'n': 1});
    expect(await ExtensionStore.I.dataGet('别的拓展', 'k'), isNull,
        reason: '存储按拓展 id 隔离');
  });

  testWidgets('给拓展的接口：配色 / 存储 / 未知方法报错', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    final bridge = ExtBridge(
        extId: 'e1',
        context: tester.element(find.byType(SizedBox)),
        store: ExtensionStore.I);

    final theme = await bridge.call('theme', null) as Map;
    expect(theme['isDark'], isFalse);
    expect(theme['accent'], matches(RegExp(r'^#[0-9a-f]{6}$')),
        reason: '配色给十六进制，拓展照着画');

    await bridge.call('storage.set', {'key': 'a', 'value': 42});
    expect(await bridge.call('storage.get', {'key': 'a'}), 42);
    await bridge.call('storage.remove', {'key': 'a'});
    expect(await bridge.call('storage.get', {'key': 'a'}), isNull);

    await expectLater(bridge.call('没有这个接口', null), throwsArgumentError);
    await expectLater(bridge.call('storage.get', null), throwsArgumentError,
        reason: '参数不对要报错，不能静默失败');
  });

  testWidgets('接口：card.setDesc 改自己卡片的简介（空串 = 不显示，落盘）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    final context = tester.element(find.byType(SizedBox));
    final bridge = ExtBridge(extId: 'e1', context: context, store: ExtensionStore.I);
    await ExtensionStore.I.add(const ExtensionItem(
        id: 'e1', name: '甲', url: 'https://a.example.com', desc: '旧简介'));

    expect(await bridge.call('card.setDesc', {'text': ' 上次同步 3 条 '}), isTrue,
        reason: '两端空白会去掉');
    expect(ExtensionStore.I.items.single.desc, '上次同步 3 条');

    await bridge.call('card.setDesc', {'text': ''});
    expect(ExtensionStore.I.items.single.desc, isEmpty, reason: '空串 = 卡片上不显示简介');

    ExtensionStore.I = ExtensionStore(); // 模拟重启
    await ExtensionStore.I.load();
    expect(ExtensionStore.I.items.single.desc, isEmpty, reason: '简介落盘了');

    await expectLater(bridge.call('card.setDesc', null), throwsArgumentError,
        reason: '参数不对要报错');
    await expectLater(
        bridge.call('card.setDesc',
            {'text': 'x' * (ExtensionItem.descMaxLength + 1)}),
        throwsArgumentError,
        reason: '超长直接报错，不静默截断');
    await expectLater(
        ExtBridge(extId: '查无此条', context: context, store: ExtensionStore.I)
            .call('card.setDesc', {'text': 'x'}),
        throwsArgumentError,
        reason: '改不了别人的 / 不在清单里的拓展');
  });

  testWidgets('接口：card.setName / card.setIcon 也能改，校验各按各的上限', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    final context = tester.element(find.byType(SizedBox));
    final bridge = ExtBridge(extId: 'e1', context: context, store: ExtensionStore.I);
    await ExtensionStore.I.add(
        const ExtensionItem(id: 'e1', name: '甲', url: 'https://a.example.com'));

    await bridge.call('card.setName', {'text': '我的成绩单'});
    expect(ExtensionStore.I.items.single.name, '我的成绩单');
    expect(ExtensionStore.I.items.single.id, 'e1', reason: '改名称不改 id');

    await bridge.call('card.setIcon', {'text': '🛠'});
    expect(ExtensionStore.I.items.single.icon, '🛠');
    await bridge.call('card.setIcon', {'text': 'https://x.example.com/i.png'});
    expect(ExtensionStore.I.items.single.iconIsImage, isTrue, reason: '图片网址照旧按图片渲染');

    await expectLater(bridge.call('card.setName', {'text': '   '}),
        throwsArgumentError, reason: '名称不能空（否则卡片没标题）');
    await expectLater(
        bridge.call('card.setName',
            {'text': 'x' * (ExtensionItem.nameMaxLength + 1)}),
        throwsArgumentError);
    await expectLater(
        bridge.call('card.setIcon', {'text': '五个字图标'}),
        throwsArgumentError,
        reason: '文字图标超过 ${ExtensionItem.iconTextMaxLength} 个字要报错');
    await expectLater(bridge.call('card.setIcon', {'text': ''}), completes,
        reason: '空串 = 回到网站 favicon / 首字，是合法的');

    ExtensionStore.I = ExtensionStore(); // 模拟重启
    await ExtensionStore.I.load();
    expect(ExtensionStore.I.items.single.name, '我的成绩单', reason: '落盘了');
    expect(ExtensionStore.I.items.single.icon, isEmpty);
  });

  testWidgets('接口：内置拓展的卡片字段也能改（落在覆盖值里，源码清单不动）', (tester) async {
    ExtensionStore.builtins = const [
      ExtensionItem(
          id: 'b1', name: '内置甲', url: 'https://a.example.com', builtin: true),
    ];
    await ExtensionStore.I.load();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    final bridge = ExtBridge(
        extId: 'b1',
        context: tester.element(find.byType(SizedBox)),
        store: ExtensionStore.I);

    await bridge.call('card.setDesc', {'text': '上次同步 3 条'});
    await bridge.call('card.setName', {'text': '内置甲（改过）'});
    expect(ExtensionStore.I.items.single.desc, '上次同步 3 条');
    expect(ExtensionStore.I.items.single.name, '内置甲（改过）');
    expect(ExtensionStore.builtins.single.name, '内置甲', reason: '源码清单里的定义不动');

    ExtensionStore.I = ExtensionStore(); // 模拟重启
    await ExtensionStore.I.load();
    expect(ExtensionStore.I.items.single.desc, '上次同步 3 条', reason: '覆盖值落盘了');

    // 用户端仍然改不了内置项本身
    await ExtensionStore.I.update(const ExtensionItem(
        id: 'b1', name: '用户改的', url: 'https://a.example.com', builtin: true));
    expect(ExtensionStore.I.items.single.name, '内置甲（改过）', reason: '内置项不给用户改');
    await ExtensionStore.I.remove('b1');
    expect(ExtensionStore.I.items, hasLength(1), reason: '内置项不给用户删');
  });

  testWidgets('卡片跟着接口改：回列表就是新简介 / 名称 / 图标', (tester) async {
    await PluginRegistry.I.enable('ext');
    await ExtensionStore.I.add(const ExtensionItem(
        id: 'e1', name: '甲', url: 'https://a.example.com', desc: '旧简介'));
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
