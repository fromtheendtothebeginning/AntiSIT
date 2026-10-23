import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **跨仓库联调检查**（只在维护者本机跑得起来，CI 里自动跳过）：
/// 拿 `AntiSIT-market` 仓库里**真实**的 `market.json` / `market.json.sig` / `dist/**`
/// 喂给 App 的这套代码，验证三件容易悄悄错位的事：
///
/// 1. 内置公钥能验通那个签名（工具与 App 各有一份 Ed25519 实现，算法/编码必须一致）；
/// 2. 目录里的 sha256 与真实 zip 对得上（工具打包 vs App 下载校验）；
/// 3. 真实 zip 能被 App 的解压器打开、找得到入口 html（工具用 archive 打包，
///    App 用另一份 archive 解压——这条不测就只会在用户手机上炸）。
///
/// 仓库不在旁边就跳过（CI 只 checkout 了 App 仓库，这个测试在那儿没意义）。
void main() {
  final repo = Directory('../AntiSIT-market');
  final skip = !repo.existsSync() ? '旁边没有 AntiSIT-market 仓库' : null;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MarketSource.I = MarketSource();
    MarketSource.publicKeys = kMarketPublicKeys;
    ExtensionStore.documentsDirectory = () async =>
        Directory.systemTemp.createTempSync('market_repo').path;
  });

  test('真实目录：验签通过 + 每条都对得上真实产物', () async {
    final catalog = File('${repo.path}/market.json').readAsBytesSync();
    final sig = File('${repo.path}/market.json.sig').readAsStringSync().trim();

    // 1) 内置公钥验通真签名
    final keyId = catalogKeyId(catalog);
    final pub = kMarketPublicKeys[keyId];
    expect(pub, isNotNull, reason: 'App 内置的公钥里得有目录声明的 keyId（$keyId）');
    expect(await verifyCatalogSignature(catalog, signature: sig, publicKey: pub!), isTrue,
        reason: '工具签的目录，App 得验得过（两份 Ed25519 实现必须一致）');

    // 2) 目录解析 + 每条产物对得上 sha256
    final entries = parseCatalog(catalog);
    expect(entries, isNotEmpty);
    for (final e in entries) {
      if (!e.isBundle) continue;
      final f = File('${repo.path}/${e.zip}');
      expect(f.existsSync(), isTrue, reason: '${e.id} 的产物 ${e.zip} 在仓库里');
      final bytes = f.readAsBytesSync();
      expect(bytes.length, e.size, reason: '${e.id} 的体积与目录记的一致');
      expect(sha256.convert(bytes).toString(), e.sha256, reason: '${e.id} 的内容哈希与目录记的一致');
    }
  }, skip: skip);

  test('真实产物：App 的解压器能打开，且入口 html 找得到', () async {
    final catalog = File('${repo.path}/market.json').readAsBytesSync();
    final tmp = Directory.systemTemp.createTempSync('market_repo_ext');
    addTearDown(() => tmp.deleteSync(recursive: true));

    for (final e in parseCatalog(catalog)) {
      if (!e.isBundle) continue;
      final bytes = File('${repo.path}/${e.zip}').readAsBytesSync();
      final bundle = extractBundle(bytes: bytes, dir: '${tmp.path}/${e.id}');
      expect(File(bundle.entry).existsSync(), isTrue, reason: '${e.id} 的入口 html 解出来了');
      expect(File(bundle.entry).readAsStringSync().toLowerCase(), contains('<html'));
    }
  }, skip: skip);

  test('真实条目能在市场页里列出来（名称 / 版本 / 权限都对）', () async {
    final signer = File('${repo.path}/market.json').readAsBytesSync();
    final entries = parseCatalog(signer);
    final byId = {for (final e in entries) e.id: e};

    expect(byId.keys, containsAll(['sit.game-2048', 'sit.game-minesweeper']));
    expect(byId['sit.game-2048']!.permissions, contains('storage'), reason: '最高分要落盘');
    expect(byId['sit.game-minesweeper']!.permissions, isEmpty,
        reason: '扫雷不存数据不联网，正好当「零权限插件」的样例');
    expect(byId['sit.game-2048']!.needsNewerApp('1.15.0'), isTrue, reason: '要求 1.16.0 以上的 App');
    expect(byId['sit.game-2048']!.needsNewerApp('1.16.0'), isFalse);
  }, skip: skip);

  // ==================== 第三方源（作者自己发的那种） ====================

  // 这个 fixture 是拿市场仓库的工具现造的（`dart run tool/market_tool.dart publish`，
  // 见市场仓库 .verify-author-source/，gitignore 掉了）。它专门盯**工具与 App 之间的
  // 字段名/格式约定**：目录里的 `publicKey` 叫什么、指纹怎么算、zip 能不能解开。
  // 造过一次之后就有得测；没造过就跳过。
  final authorRepo = Directory('../AntiSIT-market/.verify-author-source');
  final authorSkip = !File('${authorRepo.path}/market.json').existsSync()
      ? '旁边没有造过作者 fixture（市场仓库里跑 publish 生成 .verify-author-source/）'
      : null;

  test('作者源：工具写的目录，App 读得懂、验得过、装得下', () async {
    final bytes = File('${authorRepo.path}/market.json').readAsBytesSync();
    final sig = File('${authorRepo.path}/market.json.sig').readAsStringSync().trim();

    // 1) 工具内嵌的公钥：字段名与 App 的解析必须一致（跨仓库最容易悄悄错位的地方）
    final publicKey = catalogPublicKeyOf(bytes);
    expect(publicKey, isNotEmpty, reason: '作者源的目录要内嵌公钥');
    final fingerprint = keyFingerprintOf(publicKey);
    expect(fingerprint, matches(RegExp(r'^[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$')));
    // ignore: avoid_print
    print('App 算出的指纹：$fingerprint（应与工具 publish 打印的一致）');

    // 2) 用内嵌公钥验签（完整性）
    expect(await verifyCatalogSignature(bytes, signature: sig, publicKey: publicKey), isTrue);

    // 3) 解析成条目：非官方来源、base 指向该源、产物哈希对得上
    const base = 'https://cdn.jsdelivr.net/gh/someone/author-demo@main/';
    final entries = parseCatalog(bytes, base: base, sourceId: ExtSourceStore.sourceIdFor(base));
    expect(entries, isNotEmpty);
    for (final e in entries) {
      expect(e.official, isFalse, reason: '第三方条目');
      expect(e.base, base);
      if (!e.isBundle) continue;
      final zip = File('${authorRepo.path}/${e.zip}').readAsBytesSync();
      expect(sha256.convert(zip).toString(), e.sha256, reason: '${e.id} 的哈希与目录一致');
      final dir = Directory.systemTemp.createTempSync('author_ext');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bundle = extractBundle(bytes: zip, dir: '${dir.path}/${e.id}');
      expect(File(bundle.entry).existsSync(), isTrue, reason: '工具打的包 App 解得开');
    }
  }, skip: authorSkip);

  // 上面两条需要真仓库；这条只用 stub，放在最后免得跳过逻辑看花眼
  testWidgets('市场页能画出真实目录里的条目', (tester) async {
    final catalog = File('${repo.path}/market.json').readAsBytesSync();
    final sig = File('${repo.path}/market.json.sig').readAsStringSync().trim();
    MarketSource.fetcher = (Uri url) async => url.path.endsWith('.sig') ? sig.codeUnits : catalog;

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MarketView())));
    await tester.pumpAndSettle();

    for (final name in ['2048', '扫雷']) {
      expect(find.text(name), findsOneWidget, reason: '真实目录里的「$name」画出来了');
    }
    expect(find.text('安装'), findsNWidgets(2), reason: '两条都还没装');
  }, skip: skip != null);
}
