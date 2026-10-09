import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 依赖关系图的纯数据（与 widget 解耦，布局算法可单测）。
class PluginGraph {
  const PluginGraph({required this.nodes, required this.edges});

  /// 从注册表取：功能插件 + 主题插件都做节点；
  /// 硬依赖画实线（启停联动），软依赖画虚线（可选增强）。
  factory PluginGraph.fromRegistry(PluginRegistry registry) => PluginGraph(
        nodes: [
          for (final p in registry.features)
            PluginGraphNode(id: p.id, label: p.name, core: !p.removable),
          for (final t in registry.themes)
            PluginGraphNode(id: t.id, label: t.name, theme: true),
        ],
        edges: [
          for (final p in registry.features)
            for (final d in p.dependencies) PluginGraphEdge(p.id, d),
          for (final p in registry.features)
            for (final d in p.optionalDependencies) PluginGraphEdge(p.id, d, optional: true),
        ],
      );

  final List<PluginGraphNode> nodes;
  final List<PluginGraphEdge> edges;

  /// 与 [id] 直接相连的节点（两个方向都算）。
  bool linked(String a, String b) => edges
      .any((e) => (e.from == a && e.to == b) || (e.from == b && e.to == a));
}

class PluginGraphNode {
  const PluginGraphNode({
    required this.id,
    required this.label,
    this.core = false,
    this.theme = false,
  });

  final String id;
  final String label;

  /// 核心插件（不可停用）。
  final bool core;
  final bool theme;
}

/// 一条依赖边：[from] 依赖 [to]，箭头指向被依赖方。
class PluginGraphEdge {
  const PluginGraphEdge(this.from, this.to, {this.optional = false});

  final String from;
  final String to;
  final bool optional;
}

/// 分层布局结果（画布坐标，纯数据）。
class PluginGraphLayout {
  const PluginGraphLayout(this.rects, this.size, this.depth);

  final Map<String, Rect> rects;
  final Size size;

  /// 每个节点的依赖深度（0 = 不依赖任何插件）。
  final Map<String, int> depth;

  // 尺寸按最长的中文节点名（网络与登录 = 5 字）定，留一点余量即可；
  // 做小一点是为了让整张图能缩放进手机宽度（适配由 PluginGraphView 的 FittedBox 做）。
  static const double nodeW = 92;
  static const double nodeH = 38;
  static const double colGap = 28;
  static const double rowGap = 10;

  /// 布局规则：
  /// * **列 = 依赖深度**，深度大的在左（组合功能），深度 0 在右（基础件）——
  ///   于是箭头一律从左上指向右下，看的方向感稳定；
  /// * **同层内**按「邻居的平均行号」排两遍，减少连线交叉；
  /// * 硬依赖参与分层，软依赖只画线（免得可选边把层数拉乱）；
  /// * 有环时回边按 0 层算，布局不会卡死、也不会丢节点。
  static PluginGraphLayout compute(PluginGraph graph) {
    if (graph.nodes.isEmpty) {
      return const PluginGraphLayout(<String, Rect>{}, Size.zero, <String, int>{});
    }
    final hard = <String, List<String>>{
      for (final n in graph.nodes) n.id: <String>[],
    };
    for (final e in graph.edges) {
      if (e.optional) continue;
      hard[e.from]?.add(e.to);
    }

    final depth = <String, int>{};
    final visiting = <String>{};
    int depthOf(String id) {
      final cached = depth[id];
      if (cached != null) return cached;
      if (!visiting.add(id)) return 0; // 成环：回边不参与加深
      var d = 0;
      for (final dep in hard[id] ?? const <String>[]) {
        final dd = depthOf(dep) + 1;
        if (dd > d) d = dd;
      }
      visiting.remove(id);
      depth[id] = d;
      return d;
    }

    var maxDepth = 0;
    for (final n in graph.nodes) {
      final d = depthOf(n.id);
      if (d > maxDepth) maxDepth = d;
    }

    final cols = <int, List<String>>{};
    for (final n in graph.nodes) {
      cols.putIfAbsent(maxDepth - depthOf(n.id), () => <String>[]).add(n.id);
    }

    final row = <String, double>{};
    for (final ids in cols.values) {
      for (var i = 0; i < ids.length; i++) {
        row[ids[i]] = i.toDouble();
      }
    }
    for (var pass = 0; pass < 2; pass++) {
      for (final key in cols.keys.toList()..sort()) {
        final ids = cols[key]!;
        if (ids.length < 2) continue;
        final score = <String, double>{};
        for (var i = 0; i < ids.length; i++) {
          final neighbors = <double>[];
          for (final e in graph.edges) {
            if (e.from == ids[i]) {
              final o = row[e.to];
              if (o != null) neighbors.add(o);
            } else if (e.to == ids[i]) {
              final o = row[e.from];
              if (o != null) neighbors.add(o);
            }
          }
          score[ids[i]] =
              neighbors.isEmpty ? i.toDouble() : neighbors.reduce((a, b) => a + b) / neighbors.length;
        }
        final sorted = List<String>.from(ids)
          ..sort((a, b) {
            final c = score[a]!.compareTo(score[b]!);
            return c != 0 ? c : row[a]!.compareTo(row[b]!);
          });
        cols[key] = sorted;
        for (var i = 0; i < sorted.length; i++) {
          row[sorted[i]] = i.toDouble();
        }
      }
    }

    var maxRows = 1;
    for (final ids in cols.values) {
      if (ids.length > maxRows) maxRows = ids.length;
    }
    final rects = <String, Rect>{};
    for (final entry in cols.entries) {
      final ids = entry.value;
      final x = entry.key * (nodeW + colGap);
      final offset = (maxRows - ids.length) * (nodeH + rowGap) / 2; // 每列竖向居中
      for (var i = 0; i < ids.length; i++) {
        rects[ids[i]] = Rect.fromLTWH(x, offset + i * (nodeH + rowGap), nodeW, nodeH);
      }
    }
    return PluginGraphLayout(
      rects,
      Size(cols.length * (nodeW + colGap) - colGap, maxRows * (nodeH + rowGap) - rowGap),
      depth,
    );
  }
}

/// 关系图：整张图先缩放到「看得全」（只缩不放、居中），用户在这基础上双指放大、
/// 放大后拖动查看；点节点选中，选中后只高亮与它相连的边。
///
/// 适配视图这件事交给 [FittedBox]，不用 TransformationController：
/// 实测 InteractiveViewer 会把外部设进去的「小于 1」的缩放弹回 1，
/// 自己写控制器适配反而要和它打架。
class PluginGraphView extends StatelessWidget {
  const PluginGraphView({
    super.key,
    required this.graph,
    required this.layout,
    this.selected,
    this.off = const <String>{},
    this.onTap,
  });

  final PluginGraph graph;
  final PluginGraphLayout layout;
  final String? selected;

  /// 已停用的插件（画成灰的）。
  final Set<String> off;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final sel = selected;
    return InteractiveViewer(
      // 起点已经是「整张图」，所以用户只能放大；放大后边界自然会限制在内容里
      minScale: 1,
      maxScale: 4,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: layout.size.width,
            height: layout.size.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _EdgePainter(graph: graph, layout: layout, selected: sel),
                  ),
                ),
                for (final n in graph.nodes)
                  if (layout.rects[n.id] != null)
                    Positioned.fromRect(
                      rect: layout.rects[n.id]!,
                      child: _NodeCard(
                        node: n,
                        off: off.contains(n.id),
                        selected: sel == n.id,
                        // 选中某个节点后，与它无关的节点压暗，连线才看得清
                        dimmed: sel != null && sel != n.id && !graph.linked(sel, n.id),
                        onTap: onTap == null ? null : () => onTap!(n.id),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.off,
    required this.selected,
    required this.dimmed,
    this.onTap,
  });

  final PluginGraphNode node;
  final bool off;
  final bool selected;
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tint = node.theme
        ? SemColors.success
        : (node.core ? SemColors.warning : SemColors.accent);
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(SemColors.card.withValues(alpha: 0.92), SemColors.bg),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? tint : SemColors.border,
          width: selected ? 1.8 : 1,
        ),
        boxShadow: selected
            ? [BoxShadow(color: tint.withValues(alpha: 0.28), blurRadius: 10)]
            : null,
      ),
      child: Row(
        children: [
          Icon(
            node.theme
                ? Icons.palette_outlined
                : (node.core ? Icons.lock_outline : Icons.extension_outlined),
            size: 12,
            color: off ? SemColors.textMuted : tint,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              node.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: off ? SemColors.textMuted : SemColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(opacity: dimmed ? 0.35 : (off ? 0.7 : 1), child: card),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({required this.graph, required this.layout, this.selected});

  final PluginGraph graph;
  final PluginGraphLayout layout;
  final String? selected;

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in graph.edges) {
      final a = layout.rects[e.from];
      final b = layout.rects[e.to];
      if (a == null || b == null) continue;
      final focused = selected == null || selected == e.from || selected == e.to;
      final base = e.optional ? SemColors.textMuted : SemColors.accent;
      final color = base.withValues(alpha: selected == null ? 0.5 : (focused ? 0.95 : 0.15));
      final forwards = b.center.dx >= a.center.dx;
      final start = Offset(forwards ? a.right : a.left, a.center.dy);
      final end = Offset(forwards ? b.left : b.right, b.center.dy);
      final bend = (end.dx - start.dx).abs() * 0.45 + 10;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + (forwards ? bend : -bend),
          start.dy,
          end.dx - (forwards ? bend : -bend),
          end.dy,
          end.dx,
          end.dy,
        );
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = focused && selected != null ? 2 : 1.3
        ..color = color;
      if (e.optional) {
        // 虚线：软依赖
        for (final metric in path.computeMetrics()) {
          var d = 0.0;
          while (d < metric.length) {
            final next = (d + 5).clamp(0.0, metric.length);
            canvas.drawPath(metric.extractPath(d, next), stroke);
            d = next + 4;
          }
        }
      } else {
        canvas.drawPath(path, stroke);
      }
      // 箭头（指向被依赖方）
      final dir = forwards ? 1.0 : -1.0;
      canvas.drawPath(
        Path()
          ..moveTo(end.dx, end.dy)
          ..lineTo(end.dx - dir * 6, end.dy - 4)
          ..lineTo(end.dx - dir * 6, end.dy + 4)
          ..close(),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) =>
      old.graph != graph || old.layout != layout || old.selected != selected;
}
