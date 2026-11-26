import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:campus_core/campus_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 权限门覆盖范围的回归：**别人写的包**（扫码安装 / 导入压缩包）也要走权限门。
///
/// 历史症状：`ExtBridge._checkPermission` 只看 `fromMarket`，而扫码安装与 zip 导入
/// 建条目时没置这个标记，于是这些拓展不声明也能用 storage / secrets / net /
/// clipboard / notify。安装确认弹窗把这些权限列给用户看，实际一条都不拦——
/// 展示与执行不一致，比不展示更误导。
void main() {
  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ExtensionStore.I = ExtensionStore();
    ExtensionStore.builtins = const [];
    dir = Directory.systemTemp.createTempSync('ext_gate_');
    ExtensionStore.documentsDirectory = () async => dir.path;
  });

  tearDown(() {
    ScannedBundleInstaller.debugDownload = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<int> makeZip(Map<String, String> files) {
    final archive = Archive();
    files.forEach((name, content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    return ZipEncoder().encode(archive);
  }

  test('扫码安装的条目带上「权限门生效」标记，并随清单落盘/读回', () async {
    final bytes = makeZip({
      'ext.json': '{"id":"sit.qr-gate","name":"扫码拓展","version":"1.0.0",'
          '"main":"main.js","permissions":["notification"]}',
      'main.js': 'export default {}',
    });
    ScannedBundleInstaller.debugDownload = (_) async => bytes;
    final bundle = await ScannedBundleInstaller().download(ScanBundleOutcome(
      url: 'https://example.com/sit.qr-gate.zip',
      sha256: sha256.convert(bytes).toString(),
      id: 'sit.qr-gate',
      raw: 'qr',
    ));
    final item = await ScannedBundleInstaller().install(bundle);

    expect(item.gated, isTrue, reason: '扫码装的包是别人写的代码，必须受权限门约束');
    expect(item.fromMarket, isFalse, reason: '来源不是市场，但权限门照样生效');

    // 落盘后读回：标记不能丢（丢了权限门就失效）
    ExtensionStore.I = ExtensionStore();
    await ExtensionStore.I.load();
    final back = ExtensionStore.I.items.single;
    expect(back.permissionsEnforced, isTrue);
    expect(back.gated, isTrue);
  });

  testWidgets('扫码装的拓展没声明 storage：storage.* 被拒；声明了就放行', (tester) async {
    Future<ExtBridge> bridgeFor(ExtensionItem item) async {
      late ExtBridge b;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (ctx) {
            b = ExtBridge(extId: item.id, context: ctx, item: item);
            return const SizedBox();
          }),
        ),
      ));
      return b;
    }

    const undeclared = ExtensionItem(
      id: 'sit.qr-gate',
      name: '扫码拓展',
      url: '/tmp/x/main.js',
      bundled: true,
      permissionsEnforced: true,
    );
    final b1 = await bridgeFor(undeclared);
    await expectLater(
      b1.call('storage.set', {'key': 'n', 'value': 1}),
      throwsA(predicate((e) => '$e'.contains('没有声明'))),
    );

    const declared = ExtensionItem(
      id: 'sit.qr-gate',
      name: '扫码拓展',
      url: '/tmp/x/main.js',
      bundled: true,
      permissionsEnforced: true,
      permissions: ['storage'],
    );
    final b2 = await bridgeFor(declared);
    expect(await b2.call('storage.set', {'key': 'n', 'value': 1}), isTrue);
  });

  testWidgets('用户自己填网址的远程书签仍然全量放行（不误伤）', (tester) async {
    late ExtBridge b;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) {
          b = ExtBridge(
            extId: 'e1',
            context: ctx,
            item: const ExtensionItem(id: 'e1', name: '我的', url: 'https://x.example'),
          );
          return const SizedBox();
        }),
      ),
    ));
    expect(await b.call('storage.set', {'key': 'n', 'value': 2}), isTrue);
  });
}
