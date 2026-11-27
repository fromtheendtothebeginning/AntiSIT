import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plugin_ext/market/ext_dependency_plan.dart';
import 'package:plugin_ext/market/ext_dependency_sheet.dart';
import 'package:plugin_ext/market/market_entry.dart';

/// 拓展插件依赖树：角色解析、依赖规划（拓扑排序）、拒绝缺依赖、树行铺层。
void main() {
  MarketEntry entry(String id,
          {String role = 'application',
          List<Object?> requires = const [],
          List<String> api = const [],
          String version = '1.0.0'}) =>
      MarketEntry(
        id: id,
        name: id,
        desc: '',
        author: '',
        category: '工具',
        icon: '',
        type: 'bundle',
        version: version,
        url: '',
        homepage: '',
        zip: 'pkg/$id.zip',
        sha256: 'sha',
        size: 100,
        permissions: const [],
        minAppVersion: '',
        runtime: 'cordis',
        role: role,
        requires: requires,
        api: api,
      );

  final catalog = <String, MarketEntry>{
    'app-main': entry('app-main', requires: ['lib-core']),
    'lib-core': entry('lib-core', role: 'dependency', api: ['core.api'], requires: ['lib-util']),
    'lib-util': entry('lib-util', role: 'dependency', api: ['util.api']),
    'solo': entry('solo'),
    'broken': entry('broken', requires: ['not-in-catalog']),
  };

  ExtNode node(String id) => parseExtNodes([catalog[id]!]).single;

  Map<String, ExtNode> nodes() => {for (final e in catalog.values) e.id: parseExtNodes([e]).single};

  group('角色与目录解析', () {
    test('role 缺省 = 应用插件；dependency = 依赖插件（带接口）', () {
      final n = parseExtNodes([catalog['lib-core']!]).single;
      expect(n.role, ExtRole.dependency);
      expect(n.isDependency, isTrue);
      expect(n.apis, ['core.api']);
      expect(n.dependencies.single.id, 'lib-util');
    });

    test('目录里没写 role / requires / api 的老条目：应用插件、无依赖', () {
      final raw = jsonDecode(jsonEncode({
        'id': 'old-ext',
        'name': '老拓展',
        'type': 'bundle',
        'zip': 'x.zip',
        'sha256': 'h',
        'runtime': 'cordis',
      }));
      final e = MarketEntry.tryParse(raw)!;
      final n = parseExtNodes([e]).single;
      expect(n.role, ExtRole.application);
      expect(n.dependencies, isEmpty);
      expect(n.apis, isEmpty);
    });

    test('requires 可以写字符串，也可以写 {id, version}', () {
      final raw = {
        'id': 'deps-ext',
        'name': '依赖测试',
        'type': 'bundle',
        'requires': ['a', {'id': 'b', 'version': '1.2.0'}],
      };
      final e = MarketEntry.tryParse(raw)!;
      final n = parseExtNodes([e]).single;
      expect(n.dependencies.map((d) => d.id), ['a', 'b']);
      expect(n.dependencies.last.version, '1.2.0');
    });
  });

  group('安装计划（拓扑排序）', () {
    test('装应用插件：先装它的依赖，再装它自己', () {
      final plan = planExtInstall(
        target: node('app-main'),
        catalog: nodes(),
        installed: const {},
      );
      expect(plan.canInstall, isTrue);
      expect(plan.order.map((n) => n.id), ['lib-util', 'lib-core', 'app-main'],
          reason: '被依赖的先装');
      expect(plan.missing.length, 3);
    });

    test('已装够版本的依赖不再下载', () {
      final plan = planExtInstall(
        target: node('app-main'),
        catalog: nodes(),
        installed: const {'lib-util': '1.0.0', 'lib-core': '1.0.0'},
      );
      expect(plan.missing.map((n) => n.id), ['app-main']);
      expect(plan.installed.map((n) => n.id), ['lib-util', 'lib-core']);
    });

    test('已装但版本不够：算 conflicts，要跟着更新', () {
      final plan = planExtInstall(
        target: parseExtNodes([
          entry('needs-new', requires: [{'id': 'lib-core', 'version': '2.0.0'}])
        ]).single,
        catalog: nodes(),
        installed: const {'lib-core': '1.0.0', 'lib-util': '1.0.0'},
      );
      expect(plan.conflicts, contains('lib-core'));
      expect(plan.missing.map((n) => n.id), containsAll(['lib-core', 'needs-new']));
    });

    test('目录里找不到的依赖：unresolved，不能装', () {
      final plan = planExtInstall(
        target: node('broken'),
        catalog: nodes(),
        installed: const {},
      );
      expect(plan.canInstall, isFalse);
      expect(plan.unresolved, ['not-in-catalog']);
    });

    test('没有依赖的应用插件：只装自己', () {
      final plan = planExtInstall(
        target: node('solo'),
        catalog: nodes(),
        installed: const {},
      );
      expect(plan.single, isTrue);
      expect(plan.order.map((n) => n.id), ['solo']);
    });

    test('依赖成环不会转不出来（按已见过的节点截断）', () {
      final cyc = <String, MarketEntry>{
        'a': entry('a', requires: ['b']),
        'b': entry('b', requires: ['a']),
      };
      final plan = planExtInstall(
        target: parseExtNodes([cyc['a']!]).single,
        catalog: {for (final e in cyc.values) e.id: parseExtNodes([e]).single},
        installed: const {},
      );
      expect(plan.order.map((n) => n.id).toSet(), {'a', 'b'});
    });
  });

  group('树状行', () {
    test('铺成前序树：应用插件在顶层，依赖缩进一层', () {
      final plan = planExtInstall(
        target: node('app-main'),
        catalog: nodes(),
        installed: const {},
      );
      final rows = extTreeRows(plan);
      expect(rows.first.node.id, 'app-main');
      expect(rows.first.depth, 0);
      expect(rows[1].depth, 1, reason: '下一层是依赖');
      expect(rows.map((r) => r.node.id).toSet(), {'app-main', 'lib-core', 'lib-util'});
      expect(rows.where((r) => r.state == ExtTreeState.pending).length, 3);
    });

    test('已装的依赖标成「跳过」，不参与下载进度', () {
      final plan = planExtInstall(
        target: node('app-main'),
        catalog: nodes(),
        installed: const {'lib-core': '1.0.0', 'lib-util': '1.0.0'},
      );
      final rows = extTreeRows(plan, installed: const {'lib-core': '1.0.0', 'lib-util': '1.0.0'});
      expect(rows.where((r) => r.state == ExtTreeState.skipped).length, 2);
      expect(rows.firstWhere((r) => r.node.id == 'app-main').state, ExtTreeState.pending);
    });
  });

  testWidgets('树状下载界面：按 step 回传上色，完成后显示「安装完成」', (tester) async {
    final plan = planExtInstall(
      target: node('app-main'),
      catalog: nodes(),
      installed: const {},
    );
    final rows = extTreeRows(plan);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExtDependencyDownloadSheet(
          rows: rows,
          run: (onStep) async {
            // 按拓扑序走一遍
            onStep(rows[2]);
            onStep(rows[2].copyWith(state: ExtTreeState.done));
            onStep(rows[0].copyWith(state: ExtTreeState.done));
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('安装完成'), findsOneWidget);
    expect(find.text('app-main'), findsOneWidget);
    expect(find.text('lib-core'), findsOneWidget);
    expect(find.text('lib-util'), findsOneWidget);
    expect(find.text('依赖'), findsWidgets);
  });
}