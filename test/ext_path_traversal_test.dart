import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 拓展安装路径穿越的回归：市场目录条目的 `id` 会直接拼进
/// `<文档目录>/ext/<id>`，第三方源写 `../../x` 就成了任意目录递归删除 + 写文件。
///
/// 包内 `ext.json` 的 id 有 `CordisManifest.idPattern` 管，但那是**解压之后**才比对；
/// 目录里的 id 必须在下发前就挡掉。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ExtensionStore.I = ExtensionStore();
    ExtensionStore.builtins = const [];
  });

  MarketEntry? parse(Map<String, Object?> entry) =>
      MarketEntry.tryParse(entry, base: 'https://example.com/', sourceId: 'src');

  Map<String, Object?> bundle(String id) => {
        'id': id,
        'type': 'bundle',
        'name': '恶意',
        'version': '1.0.0',
        'zip': 'dist/$id.zip',
        'sha256': 'a' * 64,
      };

  test('目录条目 id 带路径分隔符 / .. / 盘符：整条跳过', () {
    for (final bad in [
      '../../evil',
      '../evil',
      'a/b',
      r'a\b',
      '/abs',
      'C:/x',
      '..',
      '',
    ]) {
      expect(parse(bundle(bad)), isNull, reason: 'id「$bad」不能进市场列表');
    }
  });

  test('合法 id 照常解析（不能被修复误伤）', () {
    for (final good in ['sit.demo-counter', 'a.b', 'ext_1', 'abc']) {
      expect(parse(bundle(good))?.id, good, reason: 'id「$good」应当通过');
    }
  });

  test('parseCatalog 会把非法 id 的条目整条剔掉', () {
    final catalog = utf8.encode(jsonEncode({
      'schema': 1,
      'extensions': [
        bundle('sit.good'),
        bundle('../../evil'),
      ],
    }));
    final entries = parseCatalog(catalog);
    expect(entries.map((e) => e.id), ['sit.good']);
  });

  test('bundleDir 兜底：非法 id 直接抛错，算出目录外的路径不返回', () async {
    final store = ExtensionStore();
    final saved = ExtensionStore.documentsDirectory;
    ExtensionStore.documentsDirectory = () async => '/tmp/exttest';
    addTearDown(() => ExtensionStore.documentsDirectory = saved);

    // 合法 id 正常拼进 ext/ 下（分隔符随平台，只比结尾）
    final dir = (await store.bundleDir('sit.good')).replaceAll('\\', '/');
    expect(dir.endsWith('/ext/sit.good'), isTrue, reason: '实际：$dir');
    await expectLater(store.bundleDir('../../evil'), throwsA(isA<StateError>()));
    await expectLater(store.bundleDir(''), throwsA(isA<StateError>()));
    await expectLater(store.bundleDir('a/b'), throwsA(isA<StateError>()));
  });
}
