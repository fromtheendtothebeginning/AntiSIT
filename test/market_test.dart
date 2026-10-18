import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:campus_core/campus_core.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:plugin_webview/plugin_webview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 插件市场的验收（目录验签 / 下载校验 / 安装更新卸载）：
///
/// * **目录必须验签**：签名不对、公钥不认识、内容被改过一个字节 → 一律不认，装不了；
/// * **拓展包必须对得上 sha256**：改过的包不解压、不落盘；
/// * 装完能与内核配合打开（zip 型解压成本地入口页，与手动导入压缩包同一条路）；
/// * 更新保持拓展 id 不变 → 它的数据（`plugin.ext.data.<id>.*`）留着；
/// * 卸载清条目 + 解压目录 + 数据；
/// * 网址型：只记一条网址，没有版本概念；
/// * minAppVersion 高于当前 App → 市场里显示「需要升级 App」，装不了。
void main() {
  late Directory tempDir;

  String hex(List<int> bytes) => sha256.convert(bytes).toString();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('market_install');
    // path_provider 在单测里没有实现：拓展解压目录直接指到临时目录
    ExtensionStore.documentsDirectory = () async => tempDir.path;
    ExtensionStore.I = ExtensionStore();
    ExtensionStore.builtins = const [];
    SiteIcon.loader = SiteIcon.forPage;
    SiteIcon.clearCache();
    MarketSource.I = MarketSource();
    MarketSource.publicKeys = kMarketPublicKeys;
    MarketSource.fetcher = httpFetcher;
    PluginRegistry.I = PluginRegistry(
      features: const [WebViewPlugin(), ExtPlugin()],
      themes: const [GlassTheme()],
      capabilities: const {PluginIds.webview: WebViewCapabilityImpl()},
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // ==================== 造一份真目录（自己签） ====================

  /// 测试里的「维护者」：现生成一对密钥，公钥塞给 App，私钥用来签目录。
  Future<Map<String, String>> newSigner() async {
    final kp = await Ed25519().newKeyPair();
    final pub = base64Encode((await kp.extractPublicKey()).bytes);
    final priv = await kp.extractPrivateKeyBytes();
    return {
      'pub': pub,
      'seed': base64Encode(priv),
      'full': base64Encode((await kp.extractPublicKey()).bytes),
    };
  }

  Future<String> sign(List<int> bytes, Map<String, String> signer) async {
    final kp = SimpleKeyPairData(
      base64Decode(signer['seed']!),
      publicKey: SimplePublicKey(base64Decode(signer['full']!), type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final sig = await Ed25519().sign(bytes, keyPair: kp);
    return base64Encode(sig.bytes);
  }

  /// 造一个 zip 压缩包（html / js / css 三件套）。
  Uint8List makeZip(Map<String, String> files) {
    final archive = Archive();
    files.forEach((name, content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// 一条目录记录 + 它的 zip，返回 (目录 JSON 字节, 签名, zip 字节)。
  Future<(List<int>, String, Uint8List)> makeCatalog({
    required Map<String, String> signer,
    String version = '1.0.0',
    String name = '记一笔',
    Map<String, String> files = const {
      'index.html': '<!doctype html><html><head></head><body>hi</body></html>',
      'app.js': 'console.log(1)',
    },
  }) async {
    final zip = makeZip(files);
    final sha = hex(zip);
    final catalog = {
      'schema': 1,
      'keyId': 'k-test',
      'extensions': [
        {
          'id': 'sit.demo-counter',
          'name': name,
          'desc': '数数小工具',
          'author': 'AntiSIT',
          'category': '工具',
          'icon': '🧮',
          'type': 'bundle',
          'version': version,
          'zip': 'dist/sit.demo-counter/$version.zip',
          'sha256': sha,
          'size': zip.length,
          'permissions': ['storage'],
          'minAppVersion': '1.0.0',
        }
      ],
    };
    final bytes = utf8.encode('${const JsonEncoder.withIndent('  ').convert(catalog)}\n');
    return (bytes, await sign(bytes, signer), zip);
  }

  /// 把「网络」换成一个内存里的镜像。
  void serveMirror({
    required List<int> catalog,
    required String sig,
    Map<String, List<int>> files = const {},
  }) {
    MarketSource.fetcher = (Uri url) async {
      // 镜像地址形态不一（jsDelivr 会多一层 gh/owner/repo@main/），按后缀认
      final path = Uri.decodeComponent(url.path);
      if (path.endsWith('market.json')) return catalog;
      if (path.endsWith('market.json.sig')) return utf8.encode(sig);
      for (final f in files.entries) {
        if (path.endsWith(f.key)) return f.value;
      }
      throw StateError('HTTP 404：$path');
    };
  }

  // ==================== 目录 ====================

  group('目录', () {
    test('验签通过：拿得到条目', () async {
      final signer = await newSigner();
      MarketSource.publicKeys = {'k-test': signer['pub']!};
      final (catalog, sig, zip) = await makeCatalog(signer: signer);
      serveMirror(catalog: catalog, sig: sig, files: {'dist/sit.demo-counter/1.0.0.zip': zip});

      await MarketSource.I.load();
      expect(MarketSource.I.status, MarketStatus.ready);
      expect(MarketSource.I.entries.single.name, '记一笔');
      expect(MarketSource.I.entries.single.sha256, hex(zip));
      expect(MarketSource.I.fromCache, isFalse);
    });

    test('目录被改过（签名对不上）→ 不认，一条都装不了', () async {
      final signer = await newSigner();
      MarketSource.publicKeys = {'k-test': signer['pub']!};
      final (catalog, sig, _) = await makeCatalog(signer: signer);
      // 改一个字：把简介换掉，签名还是老的
      final tampered = utf8.encode(utf8.decode(catalog).replaceAll('数数小工具', '别人的东西'));
      serveMirror(catalog: tampered, sig: sig);

      await MarketSource.I.load();
      expect(MarketSource.I.status, MarketStatus.failed);
      expect(MarketSource.I.entries, isEmpty);
      expect(MarketSource.I.error, contains('签名校验不过'));
    });

    test('别的私钥签的目录 → 不认（镜像伪造不了）', () async {
      final mine = await newSigner();
      final attacker = await newSigner();
      MarketSource.publicKeys = {'k-test': mine['pub']!};
      final (catalog, sig, _) = await makeCatalog(signer: attacker);
      serveMirror(catalog: catalog, sig: sig);

      await MarketSource.I.load();
      expect(MarketSource.I.status, MarketStatus.failed);
      expect(MarketSource.I.error, contains('签名校验不过'));
    });

    test('目录用的密钥 App 不认识 → 提示升级 App，而不是照装', () async {
      final signer = await newSigner();
      final (catalog, sig, _) = await makeCatalog(signer: signer);
      MarketSource.publicKeys = const {'k-other': 'AAAA'};
      serveMirror(catalog: catalog, sig: sig);

      await MarketSource.I.load();
      expect(MarketSource.I.status, MarketStatus.failed);
      expect(MarketSource.I.error, contains('不认识'));
    });

    test('网络不通：退回上次验签通过的缓存，并说明用的是缓存', () async {
      final signer = await newSigner();
      MarketSource.publicKeys = {'k-test': signer['pub']!};
      final (catalog, sig, zip) = await makeCatalog(signer: signer);
      serveMirror(catalog: catalog, sig: sig, files: {'dist/sit.demo-counter/1.0.0.zip': zip});
      await MarketSource.I.load();
      expect(MarketSource.I.ready, isTrue);

      // 换个实例（模拟重启）且网络全挂
      MarketSource.I = MarketSource();
      MarketSource.fetcher = (Uri url) async => throw const SocketException('没网');
      await MarketSource.I.load();
      expect(MarketSource.I.ready, isTrue);
      expect(MarketSource.I.entries.single.id, 'sit.demo-counter');
      expect(MarketSource.I.error, contains('缓存'));
    });

    test('缓存坏了也不认（缓存同样要验签）', () async {
      final signer = await newSigner();
      MarketSource.publicKeys = {'k-test': signer['pub']!};
      final (catalog, sig, zip) = await makeCatalog(signer: signer);
      serveMirror(catalog: catalog, sig: sig, files: {'dist/sit.demo-counter/1.0.0.zip': zip});
      await MarketSource.I.load();

      final sp = await SharedPreferences.getInstance();
      await sp.setString('plugin.ext.market.sig', base64Encode(List<int>.filled(64, 7)));
      MarketSource.I = MarketSource();
      MarketSource.fetcher = (Uri url) async => throw const SocketException('没网');
      await MarketSource.I.load();
      expect(MarketSource.I.status, MarketStatus.failed);
    });
  });

  // ==================== 安装 / 更新 / 卸载 ====================

  group('安装', () {
    Future<MarketEntry> readyEntry(Map<String, String> signer,
        {String version = '1.0.0', Map<String, String>? files}) async {
      MarketSource.publicKeys = {'k-test': signer['pub']!};
      final (catalog, sig, zip) = await makeCatalog(signer: signer, version: version, files: files ?? const {
        'index.html': '<!doctype html><html><head></head><body>hi</body></html>',
      });
      serveMirror(catalog: catalog, sig: sig, files: {'dist/sit.demo-counter/$version.zip': zip});
      await MarketSource.I.load(force: true); // 每次都是新目录，强制重拉
      return MarketSource.I.entries.single;
    }

    test('装得下来：解压成本地入口页、入列，且带版本与来源', () async {
      final signer = await newSigner();
      final entry = await readyEntry(signer);
      final item = await MarketInstaller().install(entry);

      expect(File(item.url).existsSync(), isTrue, reason: '入口 html 真的落盘了');
      expect(item.bundled, isTrue);
      expect(item.version, '1.0.0');
      expect(item.sha256, entry.sha256);
      expect(item.permissions, ['storage']);
      expect(item.fromMarket, isTrue);
      expect(ExtensionStore.I.items.single.id, 'sit.demo-counter');
      expect(MarketInstaller().isInstalled('sit.demo-counter'), isTrue);
    });

    test('包被改过（sha256 对不上）→ 不落盘、不入列', () async {
      final signer = await newSigner();
      final entry = await readyEntry(signer);
      // 下载时给一份被改过的包
      MarketSource.fetcher = (Uri url) async => utf8.encode('这不是那个 zip');
      await expectLater(MarketInstaller().install(entry),
          throwsA(predicate((e) => '$e'.contains('不一致'))));
      expect(ExtensionStore.I.items, isEmpty);
      final dir = Directory('${tempDir.path}/ext/sit.demo-counter');
      expect(dir.existsSync(), isFalse, reason: '校验在解压之前：连目录都不该建');
    });

    test('更新：内容换了、版本升了，数据留着（id 不变）', () async {
      final signer = await newSigner();
      final v1 = await readyEntry(signer, version: '1.0.0');
      await MarketInstaller().install(v1);
      await ExtensionStore.I.dataSet('sit.demo-counter', 'count', 7);
      await ExtensionStore.I.setCard('sit.demo-counter', name: '我改的名字');

      final v2 = await readyEntry(signer,
          version: '1.1.0', files: {'index.html': '<!doctype html><body>新版本</body>'});
      expect(MarketInstaller().hasUpdate(v2), isTrue);
      await MarketInstaller().install(v2);

      final after = ExtensionStore.I.items.single;
      expect(after.version, '1.1.0');
      expect(after.sha256, v2.sha256);
      expect(after.name, '我改的名字', reason: '卡片上改过的名字不该被更新冲掉');
      expect(await ExtensionStore.I.dataGet('sit.demo-counter', 'count'), 7,
          reason: '更新只换内容，数据留着');
      expect(File(after.url).readAsStringSync(), contains('新版本'));
    });

    test('同版本但内容变了也算有更新（作者重发同一版）', () async {
      final signer = await newSigner();
      final v1 = await readyEntry(signer, version: '1.0.0');
      await MarketInstaller().install(v1);

      final same = await readyEntry(signer,
          version: '1.0.0', files: {'index.html': '<!doctype html><body>改了点东西</body>'});
      expect(MarketInstaller().hasUpdate(same), isTrue);
    });

    test('没装过 / 已是最新：没有更新', () async {
      final signer = await newSigner();
      final v1 = await readyEntry(signer);
      expect(MarketInstaller().hasUpdate(v1), isFalse, reason: '还没装');
      await MarketInstaller().install(v1);
      expect(MarketInstaller().hasUpdate(v1), isFalse, reason: '装的就是最新版');
    });

    test('卸载：条目、解压目录、数据一起清', () async {
      final signer = await newSigner();
      final entry = await readyEntry(signer);
      final item = await MarketInstaller().install(entry);
      await ExtensionStore.I.dataSet(entry.id, 'count', 1);
      final dir = Directory('${tempDir.path}/ext/${entry.id}');
      expect(dir.existsSync(), isTrue);

      await MarketInstaller().uninstall(entry.id);
      expect(ExtensionStore.I.items, isEmpty);
      expect(dir.existsSync(), isFalse);
      expect(await ExtensionStore.I.dataGet(entry.id, 'count'), isNull);
      expect(File(item.url).existsSync(), isFalse);
    });

    test('与内置拓展 id 冲突 → 装不了（不会把内置项改掉）', () async {
      final signer = await newSigner();
      final entry = await readyEntry(signer);
      ExtensionStore.builtins = const [
        ExtensionItem(id: 'sit.demo-counter', name: '内置同名', url: 'https://x.com'),
      ];
      await ExtensionStore.I.load();
      await expectLater(MarketInstaller().install(entry),
          throwsA(predicate((e) => '$e'.contains('冲突'))));
    });
  });

  group('网址型', () {
    test('只记一条网址；没有版本，也就没有更新', () async {
      final signer = await newSigner();
      MarketSource.publicKeys = {'k-test': signer['pub']!};
      final catalog = utf8.encode(jsonEncode({
        'schema': 1,
        'keyId': 'k-test',
        'extensions': [
          {
            'id': 'sit.web-tool',
            'name': '校园站点',
            'desc': '第三方网址',
            'author': 'AntiSIT',
            'category': '学习',
            'type': 'web',
            'url': 'https://example.com/tool',
            'permissions': [],
          }
        ],
      }));
      serveMirror(catalog: catalog, sig: await sign(catalog, signer));

      await MarketSource.I.load();
      final entry = MarketSource.I.entries.single;
      final item = await MarketInstaller().install(entry);
      expect(item.url, 'https://example.com/tool');
      expect(item.bundled, isFalse);
      expect(item.fromMarket, isTrue, reason: '市场来源要记着，权限门按它生效');
      expect(MarketInstaller().hasUpdate(entry), isFalse);
      await expectLater(MarketSource.I.download(entry.zip), throwsA(isA<StateError>()),
          reason: '网址型没有下载地址');
    });
  });

  group('市场页', () {
    Future<void> pumpMarket(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MarketView()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('列出来源与版本，装之前把要用的接口摊给用户看', (tester) async {
      final signer = await newSigner();
      MarketSource.publicKeys = {'k-test': signer['pub']!};
      final (catalog, sig, zip) = await makeCatalog(signer: signer);
      serveMirror(catalog: catalog, sig: sig, files: {'dist/sit.demo-counter/1.0.0.zip': zip});

      await pumpMarket(tester);
      expect(find.text('记一笔'), findsOneWidget);
      expect(find.text('v1.0.0'), findsOneWidget);
      expect(find.textContaining('AntiSIT · 工具'), findsOneWidget);
      expect(find.text('安装'), findsOneWidget);

      await tester.tap(find.text('安装'));
      await tester.pumpAndSettle();
      // 安装弹窗：来源 / 权限说明 / 装完能卸载
      expect(find.text('安装「记一笔」？'), findsOneWidget);
      expect(find.textContaining('插件市场 · AntiSIT'), findsOneWidget);
      expect(find.text('它要用的接口'), findsOneWidget);
      expect(find.textContaining('在本机保存数据'), findsOneWidget,
          reason: '声明的 storage 权限要翻成人话');
    });

    testWidgets('确认安装：入列，「安装」变成「打开」', (tester) async {
      final signer = await newSigner();
      MarketSource.publicKeys = {'k-test': signer['pub']!};
      final (catalog, sig, zip) = await makeCatalog(signer: signer);
      serveMirror(catalog: catalog, sig: sig, files: {'dist/sit.demo-counter/1.0.0.zip': zip});

      await pumpMarket(tester);
      await tester.tap(find.text('安装'));
      await tester.pumpAndSettle();
      // 弹窗里的那个「安装」（卡片上也有一个同名的）
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '安装'),
      ));
      await tester.pumpAndSettle();

      expect(ExtensionStore.I.items.single.id, 'sit.demo-counter');
      expect(find.text('打开'), findsOneWidget);
      expect(find.text('安装'), findsNothing);
    });

    testWidgets('装了之后目录里有新版 → 标「有新版」并给「更新」按钮', (tester) async {
      final signer = await newSigner();
      final v1 = await (() async {
        MarketSource.publicKeys = {'k-test': signer['pub']!};
        final (catalog, sig, zip) = await makeCatalog(signer: signer, version: '1.0.0');
        serveMirror(catalog: catalog, sig: sig, files: {'dist/sit.demo-counter/1.0.0.zip': zip});
        await MarketSource.I.load(force: true);
        return MarketSource.I.entries.single;
      })();
      await MarketInstaller().install(v1);

      // 换成 1.1.0 的目录，重新进页面
      final (catalog2, sig2, zip2) = await makeCatalog(signer: signer, version: '1.1.0');
      serveMirror(catalog: catalog2, sig: sig2, files: {'dist/sit.demo-counter/1.1.0.zip': zip2});
      MarketSource.I = MarketSource();
      await pumpMarket(tester);

      expect(find.text('有新版'), findsOneWidget);
      expect(find.text('更新'), findsOneWidget);
    });

    testWidgets('目录验签不过：说清原因并给重试，不列任何条目', (tester) async {
      final signer = await newSigner();
      final other = await newSigner();
      MarketSource.publicKeys = {'k-test': signer['pub']!};
      final (catalog, sig, _) = await makeCatalog(signer: other); // 别人签的
      serveMirror(catalog: catalog, sig: sig);

      await pumpMarket(tester);
      expect(find.text('市场目录用不了'), findsOneWidget);
      expect(find.textContaining('签名校验不过'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('记一笔'), findsNothing);
    });
  });

  group('权限门', () {
    /// 起一份最简的 ExtBridge（只要 context 挂上了就行）。
    Future<ExtBridge> bridgeFor(WidgetTester tester, ExtensionItem? item) async {
      late ExtBridge b;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (ctx) {
            b = ExtBridge(extId: 'sit.demo-counter', context: ctx, item: item);
            return const SizedBox();
          }),
        ),
      ));
      return b;
    }

    testWidgets('市场装的拓展没声明 storage → storage.* 直接拒（报错回网页）', (tester) async {
      final b = await bridgeFor(
        tester,
        const ExtensionItem(
          id: 'sit.demo-counter',
          name: '记一笔',
          url: 'https://x',
          fromMarket: true,
          permissions: [], // 没声明
        ),
      );
      await expectLater(b.call('storage.set', {'key': 'n', 'value': 1}),
          throwsA(predicate((e) => '$e'.contains('没有声明'))));
      await expectLater(b.call('storage.get', {'key': 'n'}),
          throwsA(predicate((e) => '$e'.contains('没有声明'))));
      // 基础接口不受影响
      expect(await b.call('theme', null), isA<Map>());
    });

    testWidgets('声明了 storage 就放行；用户自己加的（非市场来源）全量放行', (tester) async {
      final declared = await bridgeFor(
        tester,
        const ExtensionItem(
          id: 'sit.demo-counter',
          name: '记一笔',
          url: 'https://x',
          fromMarket: true,
          permissions: ['storage'],
        ),
      );
      expect(await declared.call('storage.set', {'key': 'n', 'value': 1}), isTrue);

      // 自己填网址加的：来源是他自己选的，不设限（老行为不变）
      final mine = await bridgeFor(
        tester,
        const ExtensionItem(id: 'e1', name: '我的', url: 'https://x'),
      );
      expect(await mine.call('storage.set', {'key': 'n', 'value': 2}), isTrue);
    });
  });

  group('minAppVersion', () {
    test('要求更高版本的 App → 这个版本装不了', () async {
      final signer = await newSigner();
      MarketSource.publicKeys = {'k-test': signer['pub']!};
      final catalog = utf8.encode(jsonEncode({
        'schema': 1,
        'keyId': 'k-test',
        'extensions': [
          {
            'id': 'sit.future',
            'name': '未来的拓展',
            'desc': '需要新内核',
            'author': 'AntiSIT',
            'category': '工具',
            'type': 'web',
            'url': 'https://example.com',
            'minAppVersion': '9.9.9',
          }
        ],
      }));
      serveMirror(catalog: catalog, sig: await sign(catalog, signer));
      await MarketSource.I.load();

      final entry = MarketSource.I.entries.single;
      expect(entry.needsNewerApp('1.16.0'), isTrue);
      expect(entry.needsNewerApp('9.9.9'), isFalse);
      expect(entry.needsNewerApp('10.0.0'), isFalse);
    });

    test('版本比较：位数不齐按 0 补，脏数据不抛异常', () {
      expect(compareVersions('1.16.0', '1.16.0'), 0);
      expect(compareVersions('1.16.1', '1.16.0'), 1);
      expect(compareVersions('1.9', '1.10'), -1);
      expect(compareVersions('2', '1.99.99'), 1);
      expect(compareVersions('1.16', '1.16.0'), 0);
      expect(compareVersions('x.y', '0.0.0'), 0);
    });
  });
}
