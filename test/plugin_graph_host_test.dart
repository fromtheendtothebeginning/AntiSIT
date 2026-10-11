import 'package:campus_service/widgets/plugin_graph.dart';
import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「二课活动等工具插件挂在工具中心，依赖关系图要画出来」的验收：
/// * 贡献了工具卡片的插件与工具中心之间有一条挂载边（虚线，不联动启停）；
/// * 挂载边不参与分层：工具插件不会因为挂载边被算出依赖深度；
/// * 没贡献工具的插件没有挂载边。
class _Fake extends FeaturePlugin {
  const _Fake(this.id, {this.deps = const [], this.withTool = false});

  @override
  final String id;
  final List<String> deps;
  final bool withTool;

  @override
  String get name => '插件$id';
  @override
  String get description => '说明 $id';
  @override
  List<String> get dependencies => deps;

  @override
  List<PluginTool> tools(PluginRegistry registry) => withTool
      ? [
          PluginTool(
            icon: Icons.extension_outlined,
            color: Colors.blue,
            title: '卡片$id',
            subtitle: () => '',
            open: () => const SizedBox.shrink(),
          ),
        ]
      : const [];
}

PluginRegistry _registry() => PluginRegistry(
      features: const [
        _Fake('tools'),
        _Fake('act', withTool: true), // 二课活动：贡献工具卡片，无声明依赖
        _Fake('net', deps: ['tools']), // 对照组：硬依赖要照常分层
        _Fake('profile'), // 对照组：不贡献工具
      ],
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PluginRegistry.I = _registry();
  });

  test('贡献工具卡片的插件与工具中心之间有挂载边', () {
    final g = PluginGraph.fromRegistry(PluginRegistry.I);
    final edge = g.edges.where((e) => e.from == 'act' && e.to == 'tools').toList();
    expect(edge, hasLength(1), reason: 'act 挂在 tools 上，要有一条边');
    expect(edge.single.host, isTrue);
    expect(edge.single.optional, isFalse);
    expect(g.linked('act', 'tools'), isTrue);
  });

  test('挂载边不参与分层：贡献工具不产生依赖深度，硬依赖照常', () {
    final layout = PluginGraphLayout.compute(PluginGraph.fromRegistry(PluginRegistry.I));
    expect(layout.depth['act'], 0, reason: '挂载边不算依赖，act 不应被拉深一层');
    expect(layout.depth['net'], 1, reason: '硬依赖照常分层');
    expect(layout.depth['tools'], 0);
  });

  test('没贡献工具的插件没有挂载边', () {
    final g = PluginGraph.fromRegistry(PluginRegistry.I);
    expect(g.edges.where((e) => e.from == 'profile'), isEmpty);
    // 工具中心自己不挂自己
    expect(g.edges.where((e) => e.from == 'tools'), isEmpty);
  });

  test('注册表里没有工具中心时不画挂载边（tools 插件被剔除的构建）', () {
    PluginRegistry.I = PluginRegistry(features: const [_Fake('act', withTool: true)]);
    final g = PluginGraph.fromRegistry(PluginRegistry.I);
    expect(g.edges.where((e) => e.host), isEmpty);
  });
}
