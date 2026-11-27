import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 跨仓库联调检查（只在维护者本机跑得起来，CI 自动跳过）：内置公钥验通真签名、目录 sha256 对得上真实 zip、真实 zip 能被 App 解开。
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
      if (!e.isCordis) continue; // 旧 html 包等市场仓库迁移后再验
      final bytes = File('${repo.path}/${e.zip}').readAsBytesSync();
      final bundle = extractBundle(bytes: bytes, dir: '${tmp.path}/${e.id}');
      expect(File(bundle.entry).existsSync(), isTrue, reason: '${e.id} 的 main.js 解出来了');
      expect(File(bundle.entry).readAsStringSync(), contains('export default'));
    }
  }, skip: skip);

  test('真实产物：源码里用到的敏感服务，条目都声明了对应权限', () async {
    // 权限门只看条目上的 permissions，漏一条那次调用就整条 reject；这里拿 App 的权限表反过来查真实目录。
    final catalog = File('${repo.path}/market.json').readAsBytesSync();
    final tmp = Directory.systemTemp.createTempSync('market_repo_perm');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final problems = <String>[];

    for (final e in parseCatalog(catalog)) {
      if (!e.isCordis) continue;
      final bytes = File('${repo.path}/${e.zip}').readAsBytesSync();
      final bundle = extractBundle(bytes: bytes, dir: '${tmp.path}/${e.id}');
      final code = File(bundle.entry).readAsStringSync();
      // 反向查：代码里调了哪个服务就必须有对应权限（net.request 要 network、net.campus 要 campus_net）。
      for (final entry in kServicePermissions.entries) {
        final service = entry.key;
        final perm = entry.value;
        if (e.permissions.contains(perm)) continue;
        if (RegExp('\\bctx\\.$service\\b').hasMatch(code)) {
          problems.add('${e.id}：用了 ctx.$service，但目录里没声明 $perm');
        }
      }
      if (RegExp(r'\bctx\.net\.request\b').hasMatch(code) &&
          !e.permissions.contains('network')) {
        problems.add('${e.id}：用了 ctx.net.request，但目录里没声明 network');
      }
      if (RegExp(r'\bctx\.net\.campus\b').hasMatch(code) &&
          !e.permissions.contains('campus_net')) {
        problems.add('${e.id}：用了 ctx.net.campus，但目录里没声明 campus_net');
      }
    }
    expect(problems, isEmpty, reason: problems.join('；'));
  }, skip: skip);

  test('真实条目能在市场页里列出来（名称 / 版本 / 权限都对）', () async {
    final signer = File('${repo.path}/market.json').readAsBytesSync();
    final entries = parseCatalog(signer);
    final byId = {for (final e in entries) e.id: e};

    expect(
        byId.keys,
        containsAll([
          'sit.game-2048',
          'sit.game-minesweeper',
          'sit.deadline-reminder',
          'sit.experiment-reminder',
        ]));
    expect(byId['sit.game-2048']!.permissions, contains('storage'), reason: '最高分要落盘');
    expect(byId['sit.game-minesweeper']!.permissions, isEmpty,
        reason: '扫雷不存数据不联网，正好当「零权限插件」的样例');
    expect(byId['sit.deadline-reminder']!.permissions,
        containsAll([
          'storage',
          'notification',
          'network',
          'secrets',
          'clipboard',
          'login',
          'background',
        ]),
        reason: '学习通截止提醒：存条目、发通知、同步学习通、登录、后台刷新');
    expect(
        byId['sit.experiment-reminder']!.permissions,
        containsAll(['storage', 'notification', 'secrets', 'campus_net', 'background']),
        reason: '大物实验提醒：存条目、发通知、加密凭据、校内明文 http、后台刷新'
            '（v1.0.0 漏了 background，手机上「开启后台刷新」直接被权限门拒掉）');
    expect(byId['sit.experiment-reminder']!.needsNewerApp('1.43.0'), isTrue,
        reason: '大物实验提醒依赖 1.44.0 的 net.campus 通道');
    expect(byId['sit.experiment-reminder']!.needsNewerApp('1.44.0'), isFalse);
    expect(byId['sit.game-2048']!.needsNewerApp('1.24.0'), isTrue, reason: '要求 1.25.0 以上的 App');
    expect(byId['sit.game-2048']!.needsNewerApp('1.25.0'), isFalse);
    expect(byId['sit.deadline-reminder']!.needsNewerApp('1.37.9'), isTrue,
        reason: '截止提醒依赖 1.38.0 的运行时权限接口与弹窗通知');
    expect(byId['sit.deadline-reminder']!.needsNewerApp('1.38.0'), isFalse);
  }, skip: skip);

  // 这个 fixture 由市场仓库的工具现造（.verify-author-source/），专门盯工具与 App 之间的字段名 / 格式约定；没造过就跳过。
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
      if (!e.isCordis) continue;
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

    // 目录里既有 bundle 也有 web 型条目：两种都要能画出来，
    // web 型的按钮文案与 bundle 不同（打开网址而不是安装包）。
    for (final name in [
      '2048',
      '扫雷',
      '学习通截止提醒',
      'SIT大物实验提醒',
      'SIT校园地图',
      'SIT融合门户',
    ]) {
      expect(find.text(name), findsOneWidget, reason: '真实目录里的「$name」画出来了');
    }
  }, skip: skip != null);
}