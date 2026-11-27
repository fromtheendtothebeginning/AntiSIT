import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_core/campus_core.dart';

/// 插件文件夹清单：解析 / 目录树 / 运行期读取（bad 数据不把目录带崩）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('文件夹清单解析', () {
    test('一个文件夹可以有多个部件（同一家厂商的两种套餐）', () {
      final folders = parsePluginFolders(const [
        {
          'package': 'plugin_ai_minimax',
          'parts': [
            {'id': 'minimax', 'kind': 'provider'},
            {'id': 'minimaxtokenplan', 'kind': 'provider'},
          ],
        },
      ]);
      expect(folders, hasLength(1));
      expect(folders.single.ids, ['minimax', 'minimaxtokenplan']);
      expect(folders.single.primary?.kind, 'provider');
    });

    test('坏数据跳过：缺 package / 路径带 .. / 认不出的 kind', () {
      final folders = parsePluginFolders(const [
        {'parts': []}, // 没 package
        {'package': 'x', 'path': '../evil', 'parts': []}, // 路径越界
        {
          'package': 'plugin_demo',
          'parts': [
            {'id': 'demo', 'kind': 'widget'}, // 认不出的 kind
            {'id': 'demo2', 'kind': 'feature'},
          ],
          'dependencies': ['network', ''],
        },
      ]);
      expect(folders, hasLength(1), reason: '只有最后一条合法');
      expect(folders.single.parts.map((p) => p.id), ['demo2']);
      expect(folders.single.dependencies, ['network'], reason: '空串被剔掉');
    });

    test('序列化往返一致', () {
      const spec = PluginFolderSpec(
        package: 'plugin_activities',
        parts: [
          PluginPartSpec(id: 'activities', kind: 'feature'),
        ],
        dependencies: ['network', 'tools'],
        optionalDependencies: ['scan'],
      );
      final back = PluginFolderSpec.fromJson(spec.toJson());
      expect(back.package, spec.package);
      expect(back.ids, spec.ids);
      expect(back.dependencies, spec.dependencies);
      expect(back.optionalDependencies, spec.optionalDependencies);
    });
  });

  test('目录树：部件按 kind 落到 lib / lib/themes / lib/providers', () {
    const spec = PluginFolderSpec(
      package: 'plugin_multi',
      parts: [
        PluginPartSpec(id: 'multi', kind: 'feature'),
        PluginPartSpec(id: 'theme.one', kind: 'theme'),
        PluginPartSpec(id: 'prov', kind: 'provider', file: 'prov/custom.dart'),
      ],
    );
    final catalog = PluginFolderCatalog.I;
    final tree = catalog.treeOf(spec);
    expect(tree.first, 'plugin_multi/');
    expect(tree, contains('lib/multi.dart'));
    expect(tree, contains('lib/themes/theme.one.dart'));
    expect(tree, contains('lib/providers/prov/custom.dart'));
  });

  group('运行期读取', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('读生成物 assets/plugin_folders.json：每个插件文件夹都有部件', () async {
      final raw = jsonDecode(
        await rootBundle.loadString('assets/plugin_folders.json'),
      );
      final folders = parsePluginFolders((raw as Map)['folders']);
      expect(folders.length, greaterThan(30), reason: '仓库里 36 个插件文件夹');
      for (final f in folders) {
        expect(f.parts, isNotEmpty, reason: '${f.package} 没部件');
      }
      final activities = folders.firstWhere((f) => f.package == 'plugin_activities');
      expect(activities.ids, ['activities']);
      expect(activities.dependencies, contains('network'));
    });
  });
}
