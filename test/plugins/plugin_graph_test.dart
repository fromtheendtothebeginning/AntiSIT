import 'package:campus_service/plugins/bootstrap.dart';
import 'package:campus_service/widgets/plugin_graph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PluginGraphNode _n(String id) => PluginGraphNode(id: id, label: id);

void main() {
  group('PluginGraph.fromRegistry', () {
    test('节点含功能插件与主题插件，边方向是「依赖方 → 被依赖方」', () {
      final graph = PluginGraph.fromRegistry(buildAppRegistry());
      expect(graph.nodes.map((n) => n.id),
          containsAll(['timetable', 'network', 'theme.glass']));
      expect(graph.nodes.firstWhere((n) => n.id == 'network').core, isTrue);
      expect(graph.nodes.firstWhere((n) => n.id == 'theme.glass').theme, isTrue);

      // 课表硬依赖网络、软依赖 AI，提醒硬依赖课表
      expect(graph.edges.any((e) => e.from == 'timetable' && e.to == 'network' && !e.optional),
          isTrue);
      expect(graph.edges.any((e) => e.from == 'timetable' && e.to == 'ai' && e.optional), isTrue);
      expect(graph.edges.any((e) => e.from == 'reminder' && e.to == 'timetable'), isTrue);
    });

    test('linked 两个方向都算相连', () {
      final graph = PluginGraph.fromRegistry(buildAppRegistry());
      expect(graph.linked('timetable', 'network'), isTrue);
      expect(graph.linked('network', 'timetable'), isTrue);
      expect(graph.linked('grades', 'electricity'), isFalse);
    });
  });

  group('分层布局', () {
    // a 依赖 b，b 依赖 c；d 不依赖任何人
    final graph = PluginGraph(
      nodes: [_n('a'), _n('b'), _n('c'), _n('d')],
      edges: [const PluginGraphEdge('a', 'b'), const PluginGraphEdge('b', 'c')],
    );

    test('按依赖深度分列，被依赖的靠右', () {
      final layout = PluginGraphLayout.compute(graph);
      expect(layout.depth, {'c': 0, 'd': 0, 'b': 1, 'a': 2});
      expect(layout.rects['a']!.left, lessThan(layout.rects['b']!.left));
      expect(layout.rects['b']!.left, lessThan(layout.rects['c']!.left));
      // 同深度的 c 与 d 在同一列
      expect(layout.rects['c']!.left, layout.rects['d']!.left);
    });

    test('每个节点都有位置，且互不重叠', () {
      final layout = PluginGraphLayout.compute(graph);
      for (final n in graph.nodes) {
        expect(layout.rects[n.id], isNotNull);
      }
      final rects = graph.nodes.map((n) => layout.rects[n.id]!).toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse,
              reason: '${graph.nodes[i].id} 与 ${graph.nodes[j].id} 重叠');
        }
      }
    });

    test('纯函数：同样的输入给同样的坐标', () {
      final a = PluginGraphLayout.compute(graph);
      final b = PluginGraphLayout.compute(graph);
      expect(a.rects, b.rects);
      expect(a.size, b.size);
    });

    test('画布尺寸包得住所有节点', () {
      final layout = PluginGraphLayout.compute(graph);
      for (final r in layout.rects.values) {
        expect(r.right, lessThanOrEqualTo(layout.size.width + 0.001));
        expect(r.bottom, lessThanOrEqualTo(layout.size.height + 0.001));
      }
      expect(layout.size.width, greaterThan(0));
      expect(layout.size.height, greaterThan(0));
    });

    test('软依赖不参与分层（不给深度加码）', () {
      final g = PluginGraph(
        nodes: [_n('p'), _n('q')],
        edges: [const PluginGraphEdge('p', 'q', optional: true)],
      );
      final layout = PluginGraphLayout.compute(g);
      expect(layout.depth['p'], 0);
      expect(layout.rects['p']!.left, layout.rects['q']!.left);
    });

    test('硬依赖成环时不会卡死，节点一个不少', () {
      final g = PluginGraph(
        nodes: [_n('x'), _n('y'), _n('z')],
        edges: [const PluginGraphEdge('x', 'y'), const PluginGraphEdge('y', 'x')],
      );
      final layout = PluginGraphLayout.compute(g);
      expect(layout.rects.keys.toSet(), {'x', 'y', 'z'});
      expect(layout.rects['x']!.overlaps(layout.rects['y']!), isFalse);
    });

    test('空图不炸', () {
      final layout = PluginGraphLayout.compute(const PluginGraph(nodes: [], edges: []));
      expect(layout.rects, isEmpty);
      expect(layout.size, Size.zero);
    });
  });
}
