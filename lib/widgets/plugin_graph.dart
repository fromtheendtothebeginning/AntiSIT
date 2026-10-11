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

/// 关系图：初始整图缩放进视口（只缩不放），之后视角可自由平移、双指缩放。
/// 节点带弹簧物理：
/// * **聚拢**——进场时节点从四周散点归位到布局位置；
/// * **排斥**——拖动一个节点会推开靠得太近的邻居；
/// * **回弹**——松手后所有节点带速度弹回原位。
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
  /// 弹簧参数：轻微欠阻尼（ratio < 1）带来一点过冲的回弹手感。
  static const double _stiffness = 170;
  static const double _dampingRatio = 0.72;

  /// 中心距小于这个值就互相排斥（nodeW 92 + 余量）。
  static const double _repelDist = 118;
  static const double _repelStrength = 30;

  /// 画布四周留白：散点进场 / 小幅排斥时节点画出布局框也还在画布内。
  /// 只能小（画布 = 布局框 + 2×margin 要仍按原始大小装进「布局框 + 余量」的视口，
  /// 见插件管理页「视口装得下时保持原始大小」的测试），节点被拖远时出框即出视角，
  /// 松手弹簧会拉回来。
  static const double _margin = 16;

  /// 位移限幅：拖多远弹多远，别飞出图。
  static const double _maxDisp = 120;

  late final Ticker _ticker = createTicker(_onTick);

  /// 物理帧信号：ticker 每跳一帧通知一次，驱动子树重建与连线重画
  /// （Ticker 本身不是 Listenable，包一层）。
  final _TickSignal _physics = _TickSignal();
  Duration? _last;

  /// 每个节点相对布局位置的位移与速度（弹簧物理的状态）。
  final Map<String, Offset> _disp = <String, Offset>{};
  final Map<String, Offset> _vel = <String, Offset>{};

  @override
  void initState() {
    super.initState();
    // 进场聚拢：从伪随机方位（按 id 散列，稳定可复现）的散点弹簧归位
    for (final n in widget.graph.nodes) {
      final h = n.id.hashCode;
      final angle = (h % 360) * math.pi / 180;
      final r = 42.0 + (h >> 4) % 48.0;
      _disp[n.id] = Offset(math.cos(angle), math.sin(angle)) * r;
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

  Size get _canvasSize => Size(
        widget.layout.size.width + _margin * 2,
        widget.layout.size.height + _margin * 2,
      );

  // ── 弹簧物理 ──

  void _onTick(Duration t) {
    final dt = _last == null ? 0.0 : ((t - _last!).inMicroseconds / 1e6).clamp(0.0, 0.033);
    _last = t;
    if (dt > 0) _step(dt);
    // dt=0 的帧（不带时长的 pump）也要发信号：节点位移靠它渲染。
    _physics.fire();
  }

  /// 推进一步物理：弹簧归位 + （有节点在动时的）排斥 + 积分。
  void _step(double dt) {
    final damping = 2 * math.sqrt(_stiffness) * _dampingRatio;
    final ids = [for (final n in widget.graph.nodes) n.id];

    // 排斥：靠得太近的节点互推（拖动中的节点按当前位置推别人，自己不被推）。
    // 只在「有节点在动」时生效：布局本身按网格排（同列间距远小于排斥半径），
    // 若静止时也算排斥，排斥会跟弹簧打架，节点永远停在布局位之外、动画收不了场。
    final active = _dragging != null ||
        ids.any((id) => (_vel[id]?.distance ?? 0) > 120);
    final accel = {for (final id in ids) id: Offset.zero};
    if (active) {
      for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = ids[i], b = ids[j];
        final pa = _target(a) + (_disp[a] ?? Offset.zero);
        final pb = _target(b) + (_disp[b] ?? Offset.zero);
        final d = pb - pa;
        final dist = d.distance;
        if (dist >= _repelDist || dist < 0.01) continue;
        final f = d / dist * ((_repelDist - dist) * _repelStrength);
          if (a != _dragging) accel[a] = accel[a]! - f;
          if (b != _dragging) accel[b] = accel[b]! + f;
        }
      }
    }

    // 弹簧归位 + 积分
    for (final id in ids) {
      if (id == _dragging) continue; // 拖动中的节点 1:1 跟手，不受力
      final x = _disp[id] ?? Offset.zero;
      final v = _vel[id] ?? Offset.zero;
      final nv = v + (x * -_stiffness + v * -damping + accel[id]!) * dt;
      _vel[id] = nv;
      _disp[id] = _clamp(x + nv * dt);
    }

    // 全部归位且无拖动 → 停表（省电，也让 pumpAndSettle 能停下来）
    final settled = _dragging == null &&
        ids.every((id) => (_disp[id]?.distance ?? 0) < 0.5 && (_vel[id]?.distance ?? 0) < 5);
    if (settled) {
      for (final id in ids) {
        _disp[id] = Offset.zero;
        _vel[id] = Offset.zero;
      }
      _ticker.stop();
      _last = null;
    }
  }

  Offset _target(String id) => widget.layout.rects[id]?.topLeft ?? Offset.zero;

  Offset _clamp(Offset o) =>
      o.distance <= _maxDisp ? o : o / o.distance * _maxDisp;

  void _startTicker() {
    if (!_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
  }

  // ── 视口平移/缩放 + 节点拖动（顶层 raw Listener 统一处理）──
  // 之前用 InteractiveViewer：它内部的 ScaleGestureRecognizer 会吞掉子树里
  // PanGestureRecognizer 的后续事件（节点拖两下就断流，连 END 都收不到），
  // 而且其 constrained 布局会把子树强约束成视口大小。干脆自己实现：
  // 单指在节点上 = 拖节点，单指在空白处 = 平移视角，双指 = 以中点为锚缩放。

  final TransformationController _tc = TransformationController();
  bool _fitted = false;

  /// 进行中的指针（双指缩放时有两根）。
  final Map<int, Offset> _pointers = <int, Offset>{};
  String? _dragging; // 正在拖动的节点；null + 单指 = 平移视角
  Offset _downGlobal = Offset.zero;
  Offset _prevGlobal = Offset.zero;
  Duration _prevStamp = Duration.zero;
  Offset _dragStartDisp = Offset.zero;
  Offset _dragStartCanvas = Offset.zero;
  Offset _panStartT = Offset.zero;
  double _zoomStartScale = 1;
  double _zoomStartSpan = 1;
  Offset _zoomStartT = Offset.zero;

  /// 缩放范围：0.4 可以缩小看全局，4 放大看细节。
  static const double _minScale = 0.4;
  static const double _maxScale = 4;

  double get _scale => _tc.value.getMaxScaleOnAxis();
  Offset get _translation =>
      Offset(_tc.value.getTranslation().x, _tc.value.getTranslation().y);

  /// 首次拿到视口尺寸后，把整张图缩放居中放进视口（初始「看得全」）。
  void _fitIfNeed(BoxConstraints cons) {
    if (_fitted) return;
    _fitted = true;
    final canvas = _canvasSize;
    if (canvas.width <= 0 || canvas.height <= 0 || !cons.hasBoundedWidth || !cons.hasBoundedHeight) {
      return;
    }
    final s =
        math.min(cons.maxWidth / canvas.width, cons.maxHeight / canvas.height).clamp(_minScale, 1.0);
    _apply(Offset(
      (cons.maxWidth - canvas.width * s) / 2,
      (cons.maxHeight - canvas.height * s) / 2,
    ), s.toDouble());
  }

  /// 写入「平移 + 缩放」矩阵（内容坐标 → 视口坐标：p' = p * s + t），并夹紧平移
  /// 让画布至少留 48px 在视口里，不会把整张图拖丢。
  void _apply(Offset t, double s) {
    final vw = _viewportSize?.width ?? 0;
    final vh = _viewportSize?.height ?? 0;
    final w = _canvasSize.width * s;
    final h = _canvasSize.height * s;
    const m = 48.0;
    final tx = vw <= 0 ? t.dx : t.dx.clamp(m - w, vw - m);
    final ty = vh <= 0 ? t.dy : t.dy.clamp(m - h, vh - m);
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

  /// 全局坐标 → 画布坐标。
  Offset _toCanvas(Offset global) =>
      MatrixUtils.transformPoint(Matrix4.inverted(_tc.value), global - _viewportOrigin);

  /// 命中测试：画布坐标落在哪个节点（按位移后的实际位置）里。
  String? _hitNode(Offset canvasPoint) {
    for (final n in widget.graph.nodes) {
      final rect = widget.layout.rects[n.id];
      if (rect == null) continue;
      final r =
          rect.shift(const Offset(_margin, _margin)).shift(_disp[n.id] ?? Offset.zero);
      if (r.contains(canvasPoint)) return n.id;
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 1) {
      _downGlobal = e.position;
      _prevGlobal = e.position;
      _prevStamp = e.timeStamp;
      final hit = _hitNode(_toCanvas(e.position));
      if (hit != null) {
        _dragging = hit;
        _dragStartDisp = _disp[hit] ?? Offset.zero;
        _dragStartCanvas = _toCanvas(e.position);
        _startTicker(); // 拖动期间跑物理：邻居要被推开
      } else {
        _panStartT = _translation;
      }
    } else if (_pointers.length == 2) {
      // 第二根手指按下：切到双指缩放，放弃节点拖动 / 平移
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
      // 双指缩放：保持两指中点下的画布点不动（focal 换成视口内坐标）
      final pts = _pointers.values.toList();
      final span = _spanOf(pts);
      final focal = (pts[0] + pts[1]) / 2 - _viewportOrigin;
      final s = (_zoomStartScale * span / _zoomStartSpan).clamp(_minScale, _maxScale);
      final t0 = _zoomStartT;
      _apply(focal - (focal - t0) / _zoomStartScale * s, s);
      return;
    }
    final drag = _dragging;
    if (drag != null) {
      final d = _toCanvas(e.position) - _dragStartCanvas;
      _disp[drag] = _clamp(_dragStartDisp + d);
    } else {
      _apply(_panStartT + (e.position - _downGlobal), _scale);
    }
    _prevGlobal = e.position;
    _prevStamp = e.timeStamp;
    _physics.fire(); // 指针事件在帧外，位移靠这次信号立即渲染
  }

  void _onPointerUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) _release(e.timeStamp, e.position);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) _release(e.timeStamp, e.position);
  }

  /// 松手：节点交还弹簧（带上最近一段速度，回弹更有手感），平移/缩放就地停住。
  void _release(Duration stamp, Offset pos) {
    final drag = _dragging;
    if (drag != null) {
      _dragging = null;
      final dtMs = stamp - _prevStamp;
      if (dtMs.inMilliseconds > 0) {
        final v = (pos - _prevGlobal) * (1000 / dtMs.inMilliseconds);
        _vel[drag] = v.distance > 800 ? v / v.distance * 800 : v; // 限幅，回弹别太猛
      }
      _startTicker(); // 全体弹簧回原位
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    // 物理运行期间每帧重建（_physics 即信号）；视角矩阵变了也要重建（_tc）。
    // 初始适配（整图缩放进视口）在 _fitIfNeed 里算好矩阵，之后自由平移缩放。
    return LayoutBuilder(
      builder: (context, cons) {
        _fitIfNeed(cons);
        // 视口铺满父给的空间：矩阵按 LayoutBuilder 的约束算平移，
        // 若视口被画布子树反推大小（松约束下 SizedBox 的尺寸会往上顶），
        // 内容就会整体错位出视口。
        return SizedBox.expand(
          child: ClipRect(
            key: _viewportKey,
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            child: AnimatedBuilder(
              animation: Listenable.merge([_physics, _tc]),
              builder: (context, _) => Transform(
                transform: _tc.value,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: _canvasSize.width,
                  height: _canvasSize.height,
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
                              disp: _disp,
                              margin: _margin,
                              repaint: _physics),
                        ),
                      ),
                      for (final n in widget.graph.nodes)
                        if (widget.layout.rects[n.id] != null)
                          Positioned.fromRect(
                            rect: widget.layout.rects[n.id]!.shift(const Offset(_margin, _margin)),
                            child: Transform.translate(
                              offset: _disp[n.id] ?? Offset.zero,
                              child: _NodeCard(
                                node: n,
                                off: widget.off.contains(n.id),
                                selected: sel == n.id,
                                // 选中某个节点后，与它无关的节点压暗，连线才看得清
                                dimmed: sel != null && sel != n.id && !widget.graph.linked(sel, n.id),
                                onTap: widget.onTap == null ? null : () => widget.onTap!(n.id),
                              ),
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
      child: Opacity(opacity: dimmed ? 0.35 : (off ? 0.7 : 1), child: card),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.graph,
    required this.layout,
    this.selected,
    this.disp = const {},
    this.margin = 0,
    super.repaint,
  });

  final PluginGraph graph;
  final PluginGraphLayout layout;
  final String? selected;

  /// 节点当前位移（弹簧物理）：连线端点跟着节点走。运行期间由 ticker 触发重画。
  final Map<String, Offset> disp;
  final double margin;

  /// 节点当前实际中心（布局位置 + 画布留白 + 位移）。
  Offset _centerOf(String id) {
    final r = layout.rects[id];
    if (r == null) return Offset.zero;
    return r.shift(Offset(margin, margin)).center + (disp[id] ?? Offset.zero);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in graph.edges) {
      final a = layout.rects[e.from];
      final b = layout.rects[e.to];
      if (a == null || b == null) continue;
      final ca = _centerOf(e.from);
      final cb = _centerOf(e.to);
      final focused = selected == null || selected == e.from || selected == e.to;
      // 虚线分两档：软依赖（可选增强）用次要文字色，挂载边（工具卡片挂在工具中心）
      // 用更淡的 textMuted——挂载关系只是「卡片显示在那一页」，比可选依赖更弱
      final base = e.optional ? SemColors.textSecondary : (e.host ? SemColors.textMuted : SemColors.accent);
      final color = base.withValues(alpha: selected == null ? 0.5 : (focused ? 0.95 : 0.15));
      final forwards = cb.dx >= ca.dx;
      // 端点从节点边缘出发：按位移后中心反推（节点尺寸不变）
      final start = Offset(
          forwards ? ca.dx + a.width / 2 : ca.dx - a.width / 2, ca.dy);
      final end = Offset(forwards ? cb.dx - b.width / 2 : cb.dx + b.width / 2, cb.dy);
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
      old.graph != graph || old.layout != layout || old.selected != selected || old.disp != disp;
}
