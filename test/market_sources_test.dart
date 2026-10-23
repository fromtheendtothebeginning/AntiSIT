import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「第三方源」的验收（作者自己发的那种，不用 PR 到官方仓库）：
///
/// * 输入解析：`所有者/仓库` → jsDelivr；https 地址原样用；格式不对直接说人话；
/// * 添加前预览：拉目录 + **用源自报的公钥验签** + 算指纹；
/// * 公钥固定：加进来之后源换了钥匙（或有人中间替换）→ 停用并说明，不静默接受；
/// * 反代/加速服务回 HTTP 200 的 HTML 错误页 → 单独报错，别说成「签名校验不过」；
/// * 安装：按条目自己的源下载、校验 sha256、落 sourceId；
/// * 同一个 id 换源装 → 拒绝（否则第三方源能顶掉官方拓展）；
/// * 界面：添加源要核对指纹，第三方条目要标出来源与「未审核」。
void main() {
  late Directory tempDir;

  String hex(List<int> b) => sha256.convert(b).toString();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('ext_source');
    ExtensionStore.documentsDirectory = () async => tempDir.path;
    ExtensionStore.I = ExtensionStore();
    ExtensionStore.builtins = const [];
    MarketSource.I = MarketSource();
    ExtSourceStore.I = ExtSourceStore();
    MarketSource.publicKeys = kMarketPublicKeys;
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // ==================== 造一个「作者的源」 ====================

  Future<Map<String, String>> newSigner() async {
    final kp = await Ed25519().newKeyPair();
    final pub = await kp.extractPublicKey();
    return {
      'pub': base64Encode(pub.bytes),
      'seed': base64Encode(await kp.extractPrivateKeyBytes()),
    };
  }

  Future<String> sign(List<int> bytes, Map<String, String> s) async {
    final kp = SimpleKeyPairData(
      base64Decode(s['seed']!),
      publicKey: SimplePublicKey(base64Decode(s['pub']!), type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final sig = await Ed25519().sign(bytes, keyPair: kp);
    return base64Encode(sig.bytes);
  }

  Uint8List makeZip(Map<String, String> files) {
    final archive = Archive();
    files.forEach((name, content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// 作者仓库里的 `market.json`（自带公钥，这是第三方源的标志）。
  Future<({List<int> catalog, String sig, Uint8List zip})> authorRepo(
    Map<String, String> signer, {
    String id = 'sit.by-author',
    String version = '1.0.0',
    String publicKeyOverride = '',
    Map<String, String>? files,
  }) async {
    final zip = makeZip(files ??
        {
          'index.html': '<!doctype html><html><head></head><body>作者的小工具</body></html>',
        });
    final catalog = utf8.encode('${const JsonEncoder.withIndent('  ').convert({
          'schema': 1,
          'keyId': 'k-author',
          'publicKey': publicKeyOverride.isEmpty ? signer['pub'] : publicKeyOverride,
          'extensions': [
            {
              'id': id,
              'name': '作者的小工具',
              'desc': '来自第三方源',
              'author': 'someone',
              'category': '工具',
              'type': 'bundle',
              'version': version,
              'zip': 'dist/$id/$version.zip',
              'sha256': hex(zip),
              'size': zip.length,
              'permissions': <String>[],
            }
          ],
        })}\n');
    return (catalog: catalog, sig: await sign(catalog, signer), zip: zip);
  }

  /// 把这个源挂到「网络」上。base 用 jsDelivr 形式，验证 App 解析出来的地址能对上。
  void serve({
    required List<int> catalog,
    required String sig,
    Map<String, List<int>> files = const {},
    bool htmlInsteadOfJson = false,
  }) {
    ExtSourceStore.fetcher = (Uri url) async {
      final path = url.path;
      if (path.endsWith('market.json') && !htmlInsteadOfJson) return catalog;
      if (path.endsWith('market.json.sig')) return utf8.encode(sig);
      for (final f in files.entries) {
        if (path.endsWith(f.key)) return f.value;
      }
      if (htmlInsteadOfJson) return utf8.encode('<html><body>502 Bad Gateway</body></html>');
      throw StateError('HTTP 404：$path');
    };
  }

  // ==================== 用例 ====================

  group('源地址解析', () {
    test('所有者/仓库 → jsDelivr；https 地址原样用（补尾斜杠）', () {
      expect(ExtSourceStore.resolveBase('someone/antisit-plugins'),
          'https://cdn.jsdelivr.net/gh/someone/antisit-plugins@main/');
      expect(ExtSourceStore.resolveBase('https://example.com/plugins'),
          'https://example.com/plugins/');
      expect(ExtSourceStore.resolveBase('https://example.com/plugins/'),
          'https://example.com/plugins/');
    });

    test('格式不对 → 说人话，不吞', () {
      expect(() => ExtSourceStore.resolveBase(''), throwsA(isA<StateError>()));
      expect(() => ExtSourceStore.resolveBase('只有一段'), throwsA(isA<StateError>()));
      expect(() => ExtSourceStore.resolveBase('http://'), throwsA(isA<StateError>()));
    });

    test('源 id 用来判断「同一 id 换源装」', () {
      expect(ExtSourceStore.sourceIdFor('https://cdn.jsdelivr.net/gh/a/b@main/'),
          'cdn.jsdelivr.net/gh/a/b@main');
    });
  });

  group('添加源', () {
    test('预览：验签通过、指纹算得出来、条目解析出来', () async {
      final signer = await newSigner();
      final repo = await authorRepo(signer);
      serve(catalog: repo.catalog, sig: repo.sig, files: {'dist/sit.by-author/1.0.0.zip': repo.zip});

      final preview = await ExtSourceStore.I.preview('someone/antisit-plugins');
      expect(preview.entries.single.id, 'sit.by-author');
      expect(preview.entries.single.official, isFalse, reason: '第三方条目');
      expect(preview.draft.publicKey, signer['pub']);
      expect(preview.draft.fingerprint, keyFingerprintOf(signer['pub']!));
      expect(preview.draft.fingerprint, matches(RegExp(r'^[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$')));
      expect(preview.draft.base, contains('someone/antisit-plugins@main'));
    });

    test('目录没有自带公钥 → 说明这不是「作者自己发的源」', () async {
      final signer = await newSigner();
      final repo = await authorRepo(signer, publicKeyOverride: ' ');
      serve(catalog: repo.catalog, sig: repo.sig);
      await expectLater(ExtSourceStore.I.preview('someone/x'),
          throwsA(predicate((e) => '$e'.contains('没有自带公钥'))));
    });

    test('签名不对 → 拒绝（别人签的目录冒充不了这个源）', () async {
      final mine = await newSigner();
      final attacker = await newSigner();
      final repo = await authorRepo(mine); // 目录声明的是 mine 的公钥
      final forged = await sign(repo.catalog, attacker); // 但用攻击者的私钥签
      serve(catalog: repo.catalog, sig: forged);
      await expectLater(ExtSourceStore.I.preview('someone/x'),
          throwsA(predicate((e) => '$e'.contains('签名校验不过'))));
    });

    test('反代回了 HTML 错误页 → 说清是「返回的不是目录」，不是签名问题', () async {
      final signer = await newSigner();
      final repo = await authorRepo(signer);
      serve(catalog: repo.catalog, sig: repo.sig, htmlInsteadOfJson: true);
      await expectLater(ExtSourceStore.I.preview('someone/x'),
          throwsA(predicate((e) => '$e'.contains('返回的不是目录'))));
    });

    test('添加后落盘：重启还能读回来（含公钥指纹）', () async {
      final signer = await newSigner();
      final repo = await authorRepo(signer);
      serve(catalog: repo.catalog, sig: repo.sig, files: {'dist/sit.by-author/1.0.0.zip': repo.zip});
      final store = ExtSourceStore.I;
      final preview = await store.preview('someone/antisit-plugins');
      await store.add(preview.draft, preview.entries);

      ExtSourceStore.I = ExtSourceStore();
      await ExtSourceStore.I.load();
      final back = ExtSourceStore.I.sources.single;
      expect(back.label, 'someone/antisit-plugins');
      expect(back.fingerprint, preview.draft.fingerprint);
      expect(ExtSourceStore.I.allEntries.single.id, 'sit.by-author');
    });
  });

  group('公钥固定与刷新', () {
    test('刷新用固定的公钥：源换了钥匙 → 停用该源并说明原因', () async {
      final signer = await newSigner();
      final repo = await authorRepo(signer);
      serve(catalog: repo.catalog, sig: repo.sig, files: {'dist/sit.by-author/1.0.0.zip': repo.zip});
      final store = ExtSourceStore.I;
      final preview = await store.preview('someone/x');
      await store.add(preview.draft, preview.entries);
      expect(store.errorsBySource, isEmpty);

      // 作者换了密钥（或有人在中间替换）：新目录自报另一把公钥、并用它签
      final other = await newSigner();
      final swapped = await authorRepo(other);
      serve(catalog: swapped.catalog, sig: swapped.sig);
      await store.refresh();

      expect(store.allEntries, isEmpty, reason: '不再列它的条目');
      expect(store.errorsBySource.values.single, contains('换了签名密钥'));
      expect(store.sources, hasLength(1), reason: '源本身留着，等用户核对指纹');
    });

    test('源拿不到（网络失败）→ 只影响这一个源，其它源照旧', () async {
      final signer = await newSigner();
      final repo = await authorRepo(signer);
      serve(catalog: repo.catalog, sig: repo.sig, files: {'dist/sit.by-author/1.0.0.zip': repo.zip});
      final store = ExtSourceStore.I;
      final preview = await store.preview('someone/x');
      await store.add(preview.draft, preview.entries);

      ExtSourceStore.fetcher = (Uri url) async => throw const SocketException('没网');
      await store.refresh();
      expect(store.errorsBySource.values.single, contains('没网'));
      expect(store.allEntries, isEmpty);
    });

    test('移除源：条目一起消失', () async {
      final signer = await newSigner();
      final repo = await authorRepo(signer);
      serve(catalog: repo.catalog, sig: repo.sig, files: {'dist/sit.by-author/1.0.0.zip': repo.zip});
      final store = ExtSourceStore.I;
      final preview = await store.preview('someone/x');
      await store.add(preview.draft, preview.entries);
      await store.remove(preview.draft.id);
      expect(store.sources, isEmpty);
      expect(store.allEntries, isEmpty);
    });
  });

  group('从第三方源安装', () {
    test('下载走条目自己的源、校验 sha256、落 sourceId', () async {
      final signer = await newSigner();
      final repo = await authorRepo(signer);
      serve(catalog: repo.catalog, sig: repo.sig, files: {'dist/sit.by-author/1.0.0.zip': repo.zip});
      final store = ExtSourceStore.I;
      final preview = await store.preview('someone/x');
      await store.add(preview.draft, preview.entries);

      final item = await MarketInstaller().install(preview.entries.single);
      expect(item.fromMarket, isTrue);
      expect(item.sourceId, preview.draft.id, reason: '记住是哪个源装的');
      expect(item.version, '1.0.0');
      expect(File(item.url).existsSync(), isTrue);
      expect(File(item.url).readAsStringSync(), contains('作者的小工具'));
    });

    test('内容被换过（sha256 对不上）→ 不落盘', () async {
      final signer = await newSigner();
      final repo = await authorRepo(signer);
      serve(catalog: repo.catalog, sig: repo.sig, files: {'dist/sit.by-author/1.0.0.zip': repo.zip});
      final store = ExtSourceStore.I;
      final preview = await store.preview('someone/x');
      await store.add(preview.draft, preview.entries);

      // 下载时给一份别的包
      ExtSourceStore.fetcher = (Uri url) async => utf8.encode('不是那个 zip');
      await expectLater(MarketInstaller().install(preview.entries.single),
          throwsA(predicate((e) => '$e'.contains('不一致'))));
      expect(ExtensionStore.I.items, isEmpty);
    });

    test('同一个 id 换源装 → 拒绝（第三方顶不掉官方拓展）', () async {
      final signer = await newSigner();
      final repo = await authorRepo(signer, id: 'sit.demo-counter');
      serve(catalog: repo.catalog, sig: repo.sig,
          files: {'dist/sit.demo-counter/1.0.0.zip': repo.zip});
      final store = ExtSourceStore.I;
      final preview = await store.preview('someone/x');
      await store.add(preview.draft, preview.entries);

      // 先装一条「官方目录来的」同 id 拓展
      await ExtensionStore.I.add(const ExtensionItem(
        id: 'sit.demo-counter',
        name: '记一笔',
        url: '/tmp/x.html',
        bundled: true,
        fromMarket: true,
      ));

      await expectLater(MarketInstaller().install(preview.entries.single),
          throwsA(predicate((e) => '$e'.contains('已经由'))));
    });

    test('同一个源自己更新：版本升了就算有更新，数据留着', () async {
      final signer = await newSigner();
      final v1 = await authorRepo(signer, version: '1.0.0');
      serve(catalog: v1.catalog, sig: v1.sig,
          files: {'dist/sit.by-author/1.0.0.zip': v1.zip});
      final store = ExtSourceStore.I;
      final p1 = await store.preview('someone/x');
      await store.add(p1.draft, p1.entries);
      await MarketInstaller().install(p1.entries.single);
      await ExtensionStore.I.dataSet('sit.by-author', 'n', 7);

      final v2 = await authorRepo(signer,
          version: '1.1.0', files: {'index.html': '<!doctype html><body>新版</body>'});
      serve(catalog: v2.catalog, sig: v2.sig,
          files: {'dist/sit.by-author/1.1.0.zip': v2.zip});
      await store.refresh();

      final entry = store.allEntries.single;
      expect(MarketInstaller().hasUpdate(entry), isTrue);
      await MarketInstaller().install(entry);
      final item = ExtensionStore.I.items.single;
      expect(item.version, '1.1.0');
      expect(await ExtensionStore.I.dataGet('sit.by-author', 'n'), 7, reason: '数据留着');
    });
  });

  group('市场页', () {
    Future<void> pumpMarket(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MarketView())));
      await tester.pumpAndSettle();
    }

    testWidgets('第三方条目列出来并标了来源，安装弹窗提醒未审核', (tester) async {
      final signer = await newSigner();
      final repo = await authorRepo(signer);
      serve(catalog: repo.catalog, sig: repo.sig, files: {'dist/sit.by-author/1.0.0.zip': repo.zip});
      final store = ExtSourceStore.I;
      final preview = await store.preview('someone/x');
      await store.add(preview.draft, preview.entries);
      MarketSource.fetcher = ExtSourceStore.fetcher;

      await pumpMarket(tester);
      expect(find.text('作者的小工具'), findsOneWidget);
      expect(find.textContaining('第三方'), findsWidgets, reason: '卡片上标了第三方');

      await tester.tap(find.text('安装'));
      await tester.pumpAndSettle();
      expect(find.textContaining('第三方源 · someone/x'), findsOneWidget);
      expect(find.textContaining('没有经过官方审核'), findsOneWidget);
    });

    testWidgets('源的入口在页面上，点开能看到官方目录与第三方源与指纹', (tester) async {
      final signer = await newSigner();
      final repo = await authorRepo(signer);
      serve(catalog: repo.catalog, sig: repo.sig, files: {'dist/sit.by-author/1.0.0.zip': repo.zip});
      final store = ExtSourceStore.I;
      final preview = await store.preview('someone/x');
      await store.add(preview.draft, preview.entries);
      MarketSource.fetcher = ExtSourceStore.fetcher;

      await pumpMarket(tester);
      await tester.tap(find.textContaining('插件源：'));
      await tester.pumpAndSettle();
      expect(find.text('官方目录'), findsOneWidget);
      expect(find.text('someone/x'), findsWidgets);
      expect(find.textContaining('公钥指纹'), findsWidgets);
      expect(find.textContaining('收录 ≠ 背书'), findsOneWidget);
    });
  });
}
