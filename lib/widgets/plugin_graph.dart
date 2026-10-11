import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:campus_core/campus_core.dart';

/// 依赖关系图的纯数据（与 widget 解耦，布局算法可单测）。
class PluginGraph {
  const PluginGraph({required this.nodes, required this.edges});

  /// 从注册表取：功能插件 + 主题插件都做节点；
  /// 硬依赖画实线（启停联动），软依赖画虚线（可选增强）。
  /// 另有**挂载边**：贡献工具卡片的插件都「挂」在工具中心页上（卡片只在那一页显示，
  /// 工具中心停用卡片就没地方出现）——通过注册表的 tools() 贡献点推出的隐式依附。
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
          if (registry.byId(PluginIds.tools) != null)
            for (final p in registry.features)
              if (p.id != PluginIds.tools && p.tools(registry).isNotEmpty)
                PluginGraphEdge(p.id, PluginIds.tools, host: true),
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
/// [host] = 挂载关系（卡片显示在对方页面上），不参与启停联动。
class PluginGraphEdge {
  const PluginGraphEdge(this.from, this.to, {this.optional = false, this.host = false});

  final String from;
  final String to;
  final bool optional;

  /// 挂载边（工具卡片 → 工具中心），与可选依赖一样画虚线、不联动启停。
  final bool host;

  /// 虚线边（可选依赖 / 挂载）不参与分层与启停联动。
  bool get soft => optional || host;
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
      if (e.soft) continue;
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

/// 关系图：真正的力导向物理布局。
///
/// 物理定律（每一帧都成立）：
/// * **引力**——每条依赖边是一根胡克弹簧：F = kSpring × 距离，**越远引力越大**，
///   把关联的插件往平衡间距拉；
/// * **斥力**——所有节点两两互斥（库仑定律）：F = kRepel / 距离²，**越近斥力越大**；
/// * **弱锚定**——每个节点另有一根很弱的弹簧拴在初始排布位：纯「引力+斥力」体系
///   没有整体支点，会慢慢漂走，弱锚定防漂移、也保住图的大致可读性；
/// * 阻尼 + 限速 + 限力保证收敛；静止后休眠省电，进场 / 拖动会唤醒。
///
/// 拖动节点 1:1 跟手，松手交给物理：被关联的引力拉回、被邻居的斥力推开，
/// 落在新平衡点。视角可自由平移、双指缩放。
class PluginGraphView extends StatefulWidget {
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
  State<PluginGraphView> createState() => _PluginGraphViewState();
}

class _PluginGraphViewState extends State<PluginGraphView> with SingleTickerProviderStateMixin {
  // ── 物理定律的系数（加速度单位：px/s²，节点质量按 1 处理）──

  /// 引力：边上的胡克弹簧（静止长度 0）→ F = kSpring × 距离，越远越大。
  static const double _kSpring = 3.0;

  /// 斥力：库仑定律 → F = kRepel / 距离²，越近越大。
  /// 与 kSpring 共同决定相连节点的平衡间距：(kRepel / kSpring)^(1/3) ≈ 120px。
  static const double _kRepel = 5.2e6;

  /// 弱锚定：拴在初始排布位的弱弹簧（约为引力的 1/5），防整体漂移。
  static const double _kAnchor = 0.6;

  /// 线性阻尼（1/s）与限幅：保证收敛、不爆炸。
  static const double _damping = 4.0;
  static const double _maxSpeed = 600;
  static const double _maxAccel = 3000;
  static const double _minDist = 30; // 斥力距离下限（除零保护）

  /// 静止阈值：全体速度低于它就休眠（拖动 / 进场会唤醒）。
  static const double _sleepSpeed = 8;

  late final Ticker _ticker = createTicker(_onTick);

  /// 物理帧信号：ticker 每跳一帧通知一次，驱动子树重建与连线重画
  /// （Ticker 本身不是 Listenable，包一层）。
  final _TickSignal _physics = _TickSignal();
  Duration? _last;

  /// 画布四周留白：节点被推/拖到画布边缘时留一点缓冲。
  static const double _margin = 16;

  /// 每个节点的**绝对画布位置**（节点矩形左上角）与速度。
  final Map<String, Offset> _pos = <String, Offset>{};
  final Map<String, Offset> _vel = <String, Offset>{};

  /// 物理画布 = **视口本身**（LayoutBuilder 给的尺寸）：初始矩阵恒为恒等，
  /// 没有缩放适配/平移夹紧/裁剪这整类问题，命中测试不依赖变换。
  /// 节点多时图会挤，双指缩小看全局即可。
  Size _canvas = Size.zero;

  /// 初始排布位（弱锚定的锚点）：分层布局给的网格位置。
  Offset _home(String id) =>
      (widget.layout.rects[id]?.topLeft ?? Offset.zero) + const Offset(_margin, _margin);

  @override
  void initState() {
    super.initState();
    // 进场：从伪随机方位（按 id 散列，稳定可复现）的散点出发，物理自己收敛成平衡布局
    for (final n in widget.graph.nodes) {
      final h = n.id.hashCode;
      final angle = (h % 360) * math.pi / 180;
      final r = 40.0 + (h >> 4) % 50.0;
      _pos[n.id] = _home(n.id) + Offset(math.cos(angle), math.sin(angle)) * r;
      _vel[n.id] = Offset.zero;
    }
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _physics.dispose();
    super.dispose();
  }

  // ── 力导向物理 ──

  void _onTick(Duration t) {
    final dt = _last == null ? 0.0 : ((t - _last!).inMicroseconds / 1e6).clamp(0.0, 0.033);
    _last = t;
    if (dt > 0) _step(dt);
    // dt=0 的帧（不带时长的 pump）也要发信号：节点位移靠它渲染。
    _physics.fire();
  }

  /// 推进一步物理：斥力（两两）+ 引力（沿边）+ 弱锚定 → 阻尼积分。
  void _step(double dt) {
    if (_canvas == Size.zero) return; // 视口还没量出来
    final ids = [for (final n in widget.graph.nodes) n.id];
    final accel = {for (final id in ids) id: Offset.zero};

    // 斥力：所有节点两两互斥，F = kRepel / d²，沿连线向外（越近越大）。
    // 拖动中的节点按当前位置推别人，自己不被推。
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = ids[i], b = ids[j];
        final d = (_pos[b] ?? Offset.zero) - (_pos[a] ?? Offset.zero);
        final dist = math.max(d.distance, _minDist);
        final f = (_kRepel / (dist * dist)).clamp(0.0, _maxAccel);
        if (d.distance < 0.01) continue;
        final dir = d / d.distance;
        if (a != _dragging) accel[a] = accel[a]! - dir * f;
        if (b != _dragging) accel[b] = accel[b]! + dir * f;
      }
    }

    // 引力：每条边一根胡克弹簧，F = kSpring × 距离，越远越大，互相拉近。
    for (final e in widget.graph.edges) {
      final pa = _pos[e.from];
      final pb = _pos[e.to];
      if (pa == null || pb == null) continue;
      final d = pb - pa;
      final dist = d.distance;
      if (dist < 0.5) continue;
      final f = math.min(_kSpring * dist, _maxAccel);
      final dir = d / dist;
      if (e.from != _dragging) accel[e.from] = accel[e.from]! + dir * f;
      if (e.to != _dragging) accel[e.to] = accel[e.to]! - dir * f;
    }

    // 弱锚定 + 阻尼积分
    final damp = math.exp(-_damping * dt);
    var maxSpeed = 0.0;
    for (final id in ids) {
      if (id == _dragging) continue; // 拖动中的节点 1:1 跟手，不受力
      final anchor = (_home(id) - (_pos[id] ?? Offset.zero)) * _kAnchor;
      var v = (_vel[id] ?? Offset.zero) + (accel[id]! + anchor) * dt;
      v = v * damp;
      final speed = v.distance;
      if (speed > _maxSpeed) v = v / speed * _maxSpeed;
      final next = (_pos[id] ?? Offset.zero) + v * dt;
      final clamped = _clampToCanvas(next);
      // 撞墙：清掉指向墙外的速度分量（物理墙）。不清的话，压在墙上的节点
      // 每帧都被斥力重新加速，速度永远降不下来，物理永远睡不了。
      if (clamped.dx != next.dx) v = Offset(0, v.dy);
      if (clamped.dy != next.dy) v = Offset(v.dx, 0);
      _vel[id] = v;
      _pos[id] = clamped;
      if (v.distance > maxSpeed) maxSpeed = v.distance;
    }

    // 全场静止且无拖动 → 休眠（省电，也让 pumpAndSettle 能停下来）
    if (_dragging == null && maxSpeed < _sleepSpeed) {
      for (final id in ids) {
        _vel[id] = Offset.zero;
      }
      _ticker.stop();
      _last = null;
    }
  }

  /// 节点位置夹在画布内（留 8px 缓冲），别被推/拖出可视范围。
  Offset _clampToCanvas(Offset o) => Offset(
        o.dx.clamp(8.0, _canvas.width - PluginGraphLayout.nodeW - 8.0),
        o.dy.clamp(8.0, _canvas.height - PluginGraphLayout.nodeH - 8.0),
      );

  void _startTicker() {
    if (!_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
  }

  // ── 节点拖动（节点自己的 Pan 手势，竞技场内层优先：拖节点不会滚动页面）──

  void _onNodePanStart(String id) {
    if (_pointers.length >= 2) return; // 双指手势进行中不抢
    _dragging = id;
    _dragStartPos = _pos[id] ?? Offset.zero;
    _dragDelta = Offset.zero;
    _startTicker(); // 拖动期间跑物理：邻居要被斥力推开
  }

  void _onNodePanUpdate(String id, DragUpdateDetails d) {
    if (_dragging != id) return;
    _dragDelta += d.delta;
    // 屏幕位移 → 画布位移（视角缩放时按比例折算），1:1 跟手
    _pos[id] = _clampToCanvas(_dragStartPos + _dragDelta / _scale);
    _physics.fire(); // 指针事件在帧外，位移靠这次信号立即渲染
  }

  void _onNodePanEnd(String id, DragEndDetails d) {
    if (_dragging != id) return;
    _dragging = null;
    final v = d.velocity.pixelsPerSecond / _scale; // 屏幕速度 → 画布速度
    _vel[id] = v.distance > _maxSpeed ? v / v.distance * _maxSpeed : v;
    _startTicker(); // 物理接管：引力 + 斥力找新平衡
  }

  void _onNodePanCancel(String id) {
    if (_dragging != id) return;
    _dragging = null;
    _startTicker();
  }

  // ── 视角平移（空白处的**水平**拖动；竖直滑动让给页面滚动，互不冲突）──

  void _onCanvasPanStart(DragStartDetails d) {
    if (_pointers.length >= 2 || _dragging != null) return;
    _panStartT = _translation;
  }

  void _onCanvasPanUpdate(DragUpdateDetails d) {
    if (_pointers.length >= 2 || _dragging != null) return;
    _apply(_panStartT + Offset(d.delta.dx, 0), _scale);
  }

  // ── 视口平移/缩放 + 节点拖动（顶层 raw Listener 统一处理）──
  // 之前用 InteractiveViewer：它内部的 ScaleGestureRecognizer 会吞掉子树里
  // PanGestureRecognizer 的后续事件（节点拖两下就断流，连 END 都收不到），
  // 而且其 constrained 布局会把子树强约束成视口大小。干脆自己实现：
  // 单指在节点上 = 拖节点，单指在空白处 = 平移视角，双指 = 以中点为锚缩放。

  final TransformationController _tc = TransformationController();

  /// 进行中的指针（双指缩放/自由拖动时有两根）。
  final Map<int, Offset> _pointers = <int, Offset>{};
  String? _dragging; // 正在拖动的节点
  Offset _dragStartPos = Offset.zero;
  Offset _dragDelta = Offset.zero; // 节点拖动累计位移（屏幕坐标）
  Offset _panStartT = Offset.zero;
  double _zoomStartScale = 1;
  double _zoomStartSpan = 1;
  Offset _zoomStartT = Offset.zero;

  /// 缩放范围：0.25 可以缩小看全局（大图初始适配可能低于 0.4），4 放大看细节。
  static const double _minScale = 0.25;
  static const double _maxScale = 4;

  double get _scale => _tc.value.getMaxScaleOnAxis();
  Offset get _translation =>
      Offset(_tc.value.getTranslation().x, _tc.value.getTranslation().y);

  /// 写入「平移 + 缩放」矩阵（内容坐标 → 视口坐标：p' = p * s + t）。
  /// 平移夹紧：放大（内容 ≥ 视口）时内容必须**覆盖**视口，不留下空隙；
  /// 缩小看全局时以居中为准、只允许 ±48px 的小幅滑动。
  void _apply(Offset t, double s) {
    final vw = _viewportSize?.width ?? 0;
    final vh = _viewportSize?.height ?? 0;
    final w = _canvas.width * s;
    final h = _canvas.height * s;
    const m = 48.0;
    double clampT(double t, double content, double view) {
      if (view <= 0) return t;
      if (content >= view) return t.clamp(view - content, 0.0);
      final c = (view - content) / 2;
      return t.clamp(c - m, c + m);
    }

    final tx = clampT(t.dx, w, vw);
    final ty = clampT(t.dy, h, vh);
    _tc.value = Matrix4.identity()
      ..translateByDouble(tx.toDouble(), ty.toDouble(), 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  /// 视口尺寸（Listener 外层拿不到约束，用 GlobalKey 量）。
  final GlobalKey _viewportKey = GlobalKey();
  Size? get _viewportSize =>
      (_viewportKey.currentContext?.findRenderObject() as RenderBox?)?.size;

  /// 视口左上角的全局坐标（指针事件给的是窗口坐标，矩阵映射的是视口内坐标）。
  Offset get _viewportOrigin {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.localToGlobal(Offset.zero) ?? Offset.zero;
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      // 第二根手指按下：切到双指缩放 / 自由拖动，放弃节点拖动。
      // （单指的手势归竞技场：节点拖动归节点，水平拖动归视角，竖直滑动归页面。）
      _dragging = null;
      _zoomStartScale = _scale;
      _zoomStartSpan = _spanOf(_pointers.values);
      _zoomStartT = _translation;
    }
  }

  double _spanOf(Iterable<Offset> points) {
    final l = points.toList();
    return l.length < 2 ? 1 : (l[0] - l[1]).distance.clamp(8.0, double.infinity);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length >= 2) {
      // 双指：以两指中点为锚缩放，中点位移即自由拖动（focal 换成视口内坐标）
      final pts = _pointers.values.toList();
      final span = _spanOf(pts);
      final focal = (pts[0] + pts[1]) / 2 - _viewportOrigin;
      final s = (_zoomStartScale * span / _zoomStartSpan).clamp(_minScale, _maxScale);
      final t0 = _zoomStartT;
      _apply(focal - (focal - t0) / _zoomStartScale * s, s);
      _physics.fire();
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    // 物理运行期间每帧重建（_physics 即信号）；视角矩阵变了也要重建（_tc）。
    // 初始适配（整图缩放进视口）在 _fitIfNeed 里算好矩阵，之后自由平移缩放。
    return LayoutBuilder(
      builder: (context, cons) {
        _canvas = cons.biggest;
        return ClipRect(
          key: _viewportKey,
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            // 空白处的**水平**拖动 = 平移视角；竖直滑动不接（让给页面上下滚动）。
            // 手势竞技场天然按方向分流：水平归这里，竖直归 ListView。
            child: GestureDetector(
              onHorizontalDragStart: _onCanvasPanStart,
              onHorizontalDragUpdate: _onCanvasPanUpdate,
              behavior: HitTestBehavior.translucent,
              child: AnimatedBuilder(
              animation: Listenable.merge([_physics, _tc]),
              builder: (context, _) => Transform(
                transform: _tc.value,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: _canvas.width,
                  height: _canvas.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            // _physics 当 repaint 信号：物理运行期间每帧重画连线，静止时不重画
                            painter: _EdgePainter(
                                graph: widget.graph,
                                layout: widget.layout,
                                selected: sel,
                                pos: _pos,
                                repaint: _physics),
                          ),
                        ),
                        for (final n in widget.graph.nodes)
                          if (_pos[n.id] != null)
                            Positioned.fromRect(
                              rect: Rect.fromLTWH(_pos[n.id]!.dx, _pos[n.id]!.dy,
                                  PluginGraphLayout.nodeW, PluginGraphLayout.nodeH),
                              child: _NodeCard(
                                node: n,
                                off: widget.off.contains(n.id),
                                selected: sel == n.id,
                                // 选中某个节点后，与它无关的节点压暗，连线才看得清
                                dimmed:
                                    sel != null && sel != n.id && !widget.graph.linked(sel, n.id),
                                onTap: widget.onTap == null ? null : () => widget.onTap!(n.id),
                                onPanStart: () => _onNodePanStart(n.id),
                                onPanUpdate: (d) => _onNodePanUpdate(n.id, d),
                                onPanEnd: (d) => _onNodePanEnd(n.id, d),
                                onPanCancel: () => _onNodePanCancel(n.id),
                              ),
                            ),
                      ],
                    ),
                ),
              ),
            ),
          ),
        ),
      );
      },
    );
  }
}

/// 关系图的画布底色：做成「内凹的井」（用页面底色，比卡面深），节点才有地方浮起来。
Color pluginGraphCanvasFill() => SemColors.bg;

/// 关系图里节点的底色＝画布上再叠一层卡面。
///
/// **别写成 `SemColors.card.withValues(alpha: …)`**：card 本身自带透明度
/// （浅色白 55% / 深色白 8%），withValues 会把它**覆盖**掉——深色下节点会被刷成
/// 近白色，而节点文字是 textPrimary（深色下＝白 95%），白底白字，整张图看不清。
Color pluginGraphNodeFill() => Color.alphaBlend(SemColors.card, pluginGraphCanvasFill());

/// 纯粹的「物理跑了一帧」信号（Ticker 不是 Listenable，包一层）。
class _TickSignal extends ChangeNotifier {
  void fire() => notifyListeners();
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.off,
    required this.selected,
    required this.dimmed,
    this.onTap,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
  });

  final PluginGraphNode node;
  final bool off;
  final bool selected;
  final bool dimmed;
  final VoidCallback? onTap;
  final VoidCallback? onPanStart;
  final ValueChanged<DragUpdateDetails>? onPanUpdate;
  final ValueChanged<DragEndDetails>? onPanEnd;
  final VoidCallback? onPanCancel;

  @override
  Widget build(BuildContext context) {
    final tint = node.theme
        ? SemColors.success
        : (node.core ? SemColors.warning : SemColors.accent);
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: pluginGraphNodeFill(),
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
      // 拖节点用节点自己的 Pan 手势：竞技场内层优先，拖节点时页面不会跟着滚
      onPanStart: (_) => onPanStart?.call(),
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      onPanCancel: onPanCancel,
      child: Opacity(opacity: dimmed ? 0.35 : (off ? 0.7 : 1), child: card),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.graph,
    required this.layout,
    this.selected,
    this.pos = const {},
    super.repaint,
  });

  final PluginGraph graph;
  final PluginGraphLayout layout;
  final String? selected;

  /// 节点当前的绝对画布位置（物理状态）：连线端点跟着节点走。
  /// 运行期间由 _physics 信号触发重画，静止时不重画。
  final Map<String, Offset> pos;

  /// 节点当前实际中心与半宽（按物理位置）。
  Offset _centerOf(String id) {
    final p = pos[id];
    if (p == null) return Offset.zero;
    return p + const Offset(PluginGraphLayout.nodeW / 2, PluginGraphLayout.nodeH / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in graph.edges) {
      if (!pos.containsKey(e.from) || !pos.containsKey(e.to)) continue;
      final ca = _centerOf(e.from);
      final cb = _centerOf(e.to);
      final focused = selected == null || selected == e.from || selected == e.to;
      // 虚线分两档：软依赖（可选增强）用次要文字色，挂载边（工具卡片挂在工具中心）
      // 用更淡的 textMuted——挂载关系只是「卡片显示在那一页」，比可选依赖更弱
      final base = e.optional
          ? SemColors.textSecondary
          : (e.host ? SemColors.textMuted : SemColors.accent);
      final color = base.withValues(alpha: selected == null ? 0.5 : (focused ? 0.95 : 0.15));
      final forwards = cb.dx >= ca.dx;
      // 端点从节点边缘出发（节点尺寸恒定）
      final start = Offset(
          forwards ? ca.dx + PluginGraphLayout.nodeW / 2 : ca.dx - PluginGraphLayout.nodeW / 2,
          ca.dy);
      final end = Offset(
          forwards ? cb.dx - PluginGraphLayout.nodeW / 2 : cb.dx + PluginGraphLayout.nodeW / 2,
          cb.dy);
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
      if (e.soft) {
        // 虚线：软依赖（长虚线）/ 挂载（短虚线更淡）
        final dash = e.host ? 3 : 5;
        final gap = e.host ? 5 : 4;
        for (final metric in path.computeMetrics()) {
          var d = 0.0;
          while (d < metric.length) {
            final next = (d + dash).clamp(0.0, metric.length);
            canvas.drawPath(metric.extractPath(d, next), stroke);
            d = next + gap;
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
      old.graph != graph || old.layout != layout || old.selected != selected || old.pos != pos;
}
