import 'dart:math' as math;

import 'package:campus_core/campus_core.dart';
import 'package:campus_service/widgets/plugin_graph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「依赖关系图力导向物理」的验收（定律：边 = 引力，越远引力越大；
/// 节点两两斥力，越近斥力越大）：
/// * 进场散点在物理作用下收敛到平衡布局并休眠（不重叠）；
/// * 拖动 1:1 跟手；松手后被关联的引力拉回平衡位置；
/// * 把节点拖向邻居时邻居被斥力推开，松手后互不重叠。
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

Future<void> pumpGraph(WidgetTester tester) async {
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
  await tester.pumpAndSettle(); // 进场物理收敛并休眠
}

Finder nodeCard(String id) => find.text('插件$id');

/// 两节点中心距。
double dist(WidgetTester tester, String a, String b) =>
    (tester.getCenter(nodeCard(a)) - tester.getCenter(nodeCard(b))).distance;

/// 全部节点两两最小中心距。
double minPairDistance(WidgetTester tester) {
  const ids = ['net', 'lib', 'a', 'b'];
  var m = double.infinity;
  for (var i = 0; i < ids.length; i++) {
    for (var j = i + 1; j < ids.length; j++) {
      m = math.min(m, dist(tester, ids[i], ids[j]));
    }
  }
  return m;
}

void main() {
  testWidgets('进场：物理收敛到平衡布局并休眠，节点互不重叠', (tester) async {
    await pumpGraph(tester);
    // pumpGraph 里的 pumpAndSettle 没超时 = 物理能收敛（休眠）本身就在验收里
    expect(minPairDistance(tester), greaterThan(70),
        reason: '斥力定律：靠得太近的节点应被推开，不该重叠');
  });

  testWidgets('拖动 1:1 跟手；松手后被关联的引力拉回平衡位置', (tester) async {
    await pumpGraph(tester);
    final before = tester.getCenter(nodeCard('a')); // a 与 lib、b 相连

    final g = await tester.startGesture(before);
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(15, -12)); // 拖远（分步喂位移）
      await tester.pump();
    }
    final released = tester.getCenter(nodeCard('a'));
    expect((released - before).distance, greaterThan(50), reason: '拖动跟手');

    await g.up();
    await tester.pumpAndSettle();
    final after = tester.getCenter(nodeCard('a'));
    expect((after - before).distance, lessThan((released - before).distance),
        reason: '引力定律：连着边的节点松手后被拉回，离原位比松手那一刻近');
    expect((after - before).distance, lessThan(60),
        reason: '引力 + 弱锚定应把它拉回原平衡附近');
  });

  testWidgets('视角：双指捏合缩放后，空白处水平拖动平移视角、竖直拖动不动（不抢页面滚动）', (tester) async {
    await pumpGraph(tester);
    Matrix4 matrix() => tester.widget<Transform>(
        find.ancestor(of: find.text('插件net'), matching: find.byType(Transform)).first).transform;
    final before = matrix().getTranslation();

    // 双指捏合放大（两指分开）
    // 双指落在画布内（视口在窗口中央 600×400，起点 (100, 400)）
    final f1 = await tester.startGesture(const Offset(250, 550));
    final f2 = await tester.startGesture(const Offset(330, 550));
    await f1.moveBy(const Offset(-40, 0));
    await f2.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await f1.up();
    await f2.up();
    await tester.pumpAndSettle();
    final scale = matrix().getMaxScaleOnAxis();
    expect(scale, greaterThan(1.2), reason: '双指分开应放大视角');

    // 空白处水平拖动 → 视角平移
    final afterZoom = matrix().getTranslation();
    final h = await tester.startGesture(const Offset(300, 550));
    for (var i = 0; i < 5; i++) {
      await h.moveBy(const Offset(24, 0));
      await tester.pump();
    }
    await h.up();
    await tester.pumpAndSettle();
    expect(matrix().getTranslation().x, greaterThan(afterZoom.x), reason: '水平拖动平移视角');

    // 竖直拖动 → 视角不动（上下滑动让给页面）
    final t = matrix().getTranslation();
    final v = await tester.startGesture(const Offset(300, 550));
    for (var i = 0; i < 5; i++) {
      await v.moveBy(const Offset(0, 24));
      await tester.pump();
    }
    await v.up();
    await tester.pumpAndSettle();
    expect(matrix().getTranslation().y, closeTo(t.y, 0.5),
        reason: '竖直滑动不属于视角手势：让给页面上下滚动');
    expect(matrix().getTranslation().x, closeTo(t.x, 0.5));
  });

  testWidgets('斥力：把节点拖向邻居，邻居被推开（越近推得越狠）', (tester) async {
    await pumpGraph(tester);
    final dragFrom = tester.getCenter(nodeCard('net'));
    final libBefore = tester.getCenter(nodeCard('lib'));

    final g = await tester.startGesture(dragFrom);
    for (var i = 0; i < 10; i++) {
      // 朝 lib 的方向拖（分步、步幅过冲）：lib 会被斥力推着逃跑，
      // 拖动路径要追着它压上去，斥力才能持续起作用
      final target = libBefore - dragFrom;
      await g.moveBy(target / 5);
      await tester.pump(const Duration(milliseconds: 100)); // 带时长：斥力充分积分
    }
    final libDuring = tester.getCenter(nodeCard('lib'));
    expect((libDuring - libBefore).distance, greaterThan(6),
        reason: '斥力定律：节点逼近时邻居被推开（lib 同时被自己的边弹簧拉住，'
            '位移是斥力与回拉力平衡的结果）');

    await g.up();
    await tester.pumpAndSettle();
    expect(minPairDistance(tester), greaterThan(70), reason: '松手后重新平衡，互不重叠');
  });
}
