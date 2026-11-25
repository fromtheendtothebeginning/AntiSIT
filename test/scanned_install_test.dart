import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:campus_core/campus_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 扫码安装：下载后先核对二维码里的 sha256、装进来的拓展带 bundled / sha256 / 权限、同 id 与内置 id 不能覆盖。
void main() {
  late Directory dir;
  late Future<String> Function() savedDocs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ExtensionStore.I = ExtensionStore();
    ExtensionStore.builtins = const [];
    dir = Directory.systemTemp.createTempSync('scanned_install_');
    savedDocs = ExtensionStore.documentsDirectory;
    ExtensionStore.documentsDirectory = () async => dir.path;
  });

  tearDown(() {
    ScannedBundleInstaller.debugDownload = null;
    ExtensionStore.documentsDirectory = savedDocs;
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

  const extJson = '{"id":"sit.qr-demo","name":"扫码拓展","desc":"扫码装的",'
      '"version":"1.0.0","main":"main.js","permissions":["notification"]}';

  Future<ScannedBundle> downloadedBundle() async {
    final bytes = makeZip({
      'ext.json': extJson,
      'main.js': 'export default { apply(ctx) { ctx.ui.root.textContent = "hi" } }',
    });
    ScannedBundleInstaller.debugDownload = (_) async => bytes;
    return ScannedBundleInstaller().download(ScanBundleOutcome(
      url: 'https://example.com/sit.qr-demo.zip',
      sha256: sha256.convert(bytes).toString(),
      id: 'sit.qr-demo',
      raw: 'qr',
    ));
  }

  test('下载校验通过后安装：解压入列，sha256 / 权限 / 版本都落进清单', () async {
    final bundle = await downloadedBundle();
    expect(bundle.manifest.name, '扫码拓展');
    expect(bundle.manifest.permissions, ['notification']);

    final item = await ScannedBundleInstaller().install(bundle);
    expect(item.id, 'sit.qr-demo');
    expect(item.bundled, isTrue);
    expect(item.runtime, ExtensionItem.runtimeCordis);
    expect(item.version, '1.0.0');
    expect(item.sha256, bundle.sha256);
    expect(item.permissions, ['notification']);
    expect(File(item.url).existsSync(), isTrue);
    expect(File(item.url).readAsStringSync(), contains('ctx.ui.root'));

    expect(ExtensionStore.I.items.single.id, 'sit.qr-demo');
  });

  test('sha256 对不上：直接拒，清单里不会多一条', () async {
    final bytes = makeZip({'ext.json': extJson, 'main.js': 'export default {}'});
    ScannedBundleInstaller.debugDownload = (_) async => bytes;

    await expectLater(
      ScannedBundleInstaller().download(ScanBundleOutcome(
        url: 'https://example.com/x.zip',
        sha256: '0' * 64,
        raw: 'qr',
      )),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains('sha256'))),
    );
    expect(ExtensionStore.I.items, isEmpty);
  });

  test('包里的 id 与二维码 id 不一致：拒装', () async {
    final bytes = makeZip({'ext.json': extJson, 'main.js': 'export default {}'});
    ScannedBundleInstaller.debugDownload = (_) async => bytes;

    await expectLater(
      ScannedBundleInstaller().download(ScanBundleOutcome(
        url: 'https://example.com/x.zip',
        sha256: sha256.convert(bytes).toString(),
        id: 'sit.other',
        raw: 'qr',
      )),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains('不一致'))),
    );
  });

  test('已存在同 id / 内置 id：不覆盖，提示先卸载或换 id', () async {
    final bundle = await downloadedBundle();
    final installer = ScannedBundleInstaller();
    await installer.install(bundle);

    await expectLater(
      installer.install(bundle),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains('已存在'))),
    );

    ExtensionStore.builtins = const [
      ExtensionItem(
          id: 'sit.qr-demo', name: '内置', url: 'https://a.example.com', builtin: true),
    ];
    await expectLater(
      installer.install(bundle),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains('内置'))),
    );
  });
}
