import 'package:campus_core/campus_core.dart';
import 'package:campus_service/widgets/plugin_graph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「依赖关系视图交互化」的验收：
/// * 进场聚拢：节点从散点弹回布局位（动画能收场，pumpAndSettle 能停）；
/// * 拖动节点 1:1 跟手，松手后回弹原处（位移归零）；
/// * 拖动会推开靠得近的邻居（排斥），松手后邻居也回位。
class _Fake extends FeaturePlugin {
  const _Fake(this.id, {this.deps = const []});

  @override
  final String id;
  final List<String> deps;

  @override
  String get name => '插件$id';
  @override
  String get description => '说明 $id';
  @override
  List<String> get dependencies => deps;
}

Future<PluginGraphLayout> pumpGraph(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  PluginRegistry.I = PluginRegistry(features: const [
    _Fake('net'), _Fake('lib'), _Fake('a', deps: ['lib']), _Fake('b', deps: ['a']),
  ]);
  final graph = PluginGraph.fromRegistry(PluginRegistry.I);
  final layout = PluginGraphLayout.compute(graph);
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 600,
          height: 400,
          child: PluginGraphView(graph: graph, layout: layout),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle(); // 进场聚拢动画收场
  return layout;
}

Finder nodeCard(String id) => find.text('插件$id');

void main() {
  testWidgets('进场聚拢：动画收场后节点间的相对位置与布局一致', (tester) async {
    // pumpGraph 里的 pumpAndSettle 没超时本身就是「聚拢动画能收场」的验收；
    // 这里再用节点间相对位置对齐布局（画布会被 FittedBox 居中，绝对坐标不可比）
    final layout = await pumpGraph(tester);
    double rel(String a, String b) =>
        (tester.getCenter(nodeCard(a)) - tester.getCenter(nodeCard(b))).distance;
    double relExpected(String a, String b) =>
        (layout.rects[a]!.center - layout.rects[b]!.center).distance;
    expect(rel('net', 'lib'), closeTo(relExpected('net', 'lib'), 1.5), reason: '同列相邻两行');
    expect(rel('a', 'net'), closeTo(relExpected('a', 'net'), 1.5), reason: '跨列两节点');
  });

  testWidgets('拖动节点跟手，松手回弹原处', (tester) async {
    await pumpGraph(tester);
    final before = tester.getCenter(nodeCard('net'));

    final g = await tester.startGesture(before);
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(5, 4)); // 小步拖动
      await tester.pump();
    }
    final during = tester.getCenter(nodeCard('net'));
    expect((during - before).distance, greaterThan(40), reason: '拖动中节点跟着手指走');

    await g.up();
    await tester.pumpAndSettle();
    final after = tester.getCenter(nodeCard('net'));
    expect((after - before).distance, lessThan(2), reason: '松手后回弹原位');
  });

  testWidgets('拖动推开邻居（排斥），松手后邻居回位', (tester) async {
    await pumpGraph(tester);
    final drag = tester.getCenter(nodeCard('net'));
    final neighborBefore = tester.getCenter(nodeCard('lib'));

    final g = await tester.startGesture(drag);
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(-10, 0)); // 往左推：挤向左边的邻居
      await tester.pump(const Duration(milliseconds: 16)); // 带时长：物理积分推进
    }
    final neighborDuring = tester.getCenter(nodeCard('lib'));
    expect((neighborDuring - neighborBefore).distance, greaterThan(2),
        reason: '排斥生效：邻居被推开');

    await g.up();
    await tester.pumpAndSettle();
    final neighborAfter = tester.getCenter(nodeCard('lib'));
    expect((neighborAfter - neighborBefore).distance, lessThan(2), reason: '邻居也回弹原位');
  });
}
