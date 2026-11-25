import 'package:campus_core/campus_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// 预测式返回的旧样式（外观设置里的 `PredictiveBackStyle.fade`）：整页淡化 + 轻微缩小 +
/// 圆角滑出，拖动 1:1 跟手，松手提交 / 取消都从松手位置续上；下层页前 1/3 淡入并经磨砂遮罩变清楚。
class PredictiveFadeBackGesture extends StatefulWidget {
  const PredictiveFadeBackGesture({
    super.key,
    required this.route,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
    required this.fallbackTransitions,
    required this.commitSpan,
  });

  final PageRoute<dynamic> route;
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;

  /// 页面本身（手势画面直接包它）。
  final Widget child;

  /// 没有手势时用的普通转场（默认前进 / 返回动画）。
  final Widget fallbackTransitions;

  /// 松手提交后滑出占框架反向时长窗口的比例（固定 ≈180ms 换算而来）。
  final double commitSpan;

  @override
  State<PredictiveFadeBackGesture> createState() =>
      _PredictiveFadeBackGestureState();
}

/// 返回手势所处的阶段，决定画面由哪个分支驱动。
enum _BackPhase {
  /// 没参与这次手势，走默认转场。
  none,

  /// 手指还在屏幕上，位移 1:1 跟手。
  drag,

  /// 松手提交，从松手位置继续滑出并淡出。
  commit,

  /// 松手取消，从松手位置滑回原位。
  return_,
}

/// 手势期间的覆盖率（1 = 顶层页全盖住下层，0 = 已滑走，null = 无手势），被盖住的页据此做渐进磨砂。
final ValueNotifier<double?> predictiveBackCover = ValueNotifier<double?>(null);

/// 覆盖率 → 下层磨砂遮罩不透明度（0..0.45）：手势前 1/3 最重，1/3 → 2/3 线性变清楚。
/// 用纯色遮罩而非高斯模糊：全屏 ImageFiltered 会逐帧 saveLayer，中低端机收尾掉帧。
double _coverFrost(double v) =>
    0.45 * (1 - (((1 - v) - 1 / 3) / (1 / 3)).clamp(0.0, 1.0));

class _PredictiveFadeBackGestureState extends State<PredictiveFadeBackGesture>
    with WidgetsBindingObserver {
  /// 固定按「从左返回」：不论手指从哪条边划入，当前页都往右滑出。
  static const double _dir = 1;

  /// 拖动期间当前页最多淡掉多少（1.0 = 进度 1/3 时只剩 67% 不透明度）。
  static const double _dragFade = 1.0;

  _BackPhase _phase = _BackPhase.none;

  /// 松手那一刻的动画值（= 1 - 手势进度），提交 / 取消的动画都从它续上，避免跳变。
  double _releaseV = 1;

  /// 提交后 controller 反弹到的最大值（正常是 1.0，见 [_commitT]）。
  double _commitFrom = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 手势期间把覆盖率发布给被盖住的页（监听在帧调度阶段触发，不在 build 里改 ValueNotifier）。
    widget.animation.addListener(_publishCover);
  }

  /// 把手势进度发布成覆盖率，手势结束后置 null。
  void _publishCover() {
    if (_phase == _BackPhase.none) return;
    final v = widget.animation.value.clamp(0.0, 1.0);
    final done = (_phase == _BackPhase.return_ && v >= 1.0) ||
        (_phase == _BackPhase.commit && v <= 0.0);
    if (done) {
      predictiveBackCover.value = null;
    } else if (_phase == _BackPhase.commit) {
      if (v > _commitFrom) _commitFrom = v;
      // 按「实际滑出进度」发布，框架把动画值拉回 1.0 的那一跳不能外漏，否则下层页会闪一下。
      predictiveBackCover.value = _releaseV * (1 - _commitT(v));
    } else {
      predictiveBackCover.value = v;
    }
  }

  /// 提交后滑出的进度（0 = 刚松手，1 = 滑完）：只用窗口前 [commitSpan] 走完。
  double _commitT(double v) {
    if (_commitFrom <= 0) return 0;
    final u = ((_commitFrom - v) / _commitFrom).clamp(0.0, 1.0);
    return (u / widget.commitSpan).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    widget.animation.removeListener(_publishCover);
    if (_phase != _BackPhase.none) predictiveBackCover.value = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // WidgetsBindingObserver：接管系统返回手势，其余交给 Flutter 自己的路由实现

  /// 开始接管：按键返回、被压住的页、关掉预测式返回或不是 fade 样式时都放行给别的观察者。
  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (backEvent.isButtonEvent ||
        !AppState.I.predictiveBack ||
        AppState.I.predictiveBackStyle != PredictiveBackStyle.fade ||
        !widget.route.isCurrent ||
        !widget.route.popGestureEnabled) {
      return false;
    }
    widget.route.handleStartBackGesture(progress: 1 - backEvent.progress);
    if (mounted) {
      setState(() => _phase = _BackPhase.drag);
    }
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) =>
      widget.route.handleUpdateBackGestureProgress(
          progress: 1 - backEvent.progress);

  @override
  void handleCancelBackGesture() {
    _releaseV = widget.animation.value;
    // 松手回弹：路由自己把动画走回去
    widget.route.handleCancelBackGesture();
    if (mounted) setState(() => _phase = _BackPhase.return_);
    // 兜底收尾：拖回起点才松手时框架不会再跑回位动画，覆盖率会停在旧值上（该页会渲染成空白）。
    _publishCover();
  }

  @override
  void handleCommitBackGesture() {
    _releaseV = widget.animation.value;
    _commitFrom = 0;
    // 相位必须先切：route.handleCommitBackGesture() 会把动画值拉回 1.0，那一跳会同步通知 _publishCover。
    if (mounted) setState(() => _phase = _BackPhase.commit);
    widget.route.handleCommitBackGesture();
    // 兜底收尾：拖到底才松手时框架不会再跑动画，覆盖率得在这里自己清掉。
    _publishCover();
  }

  static double _mix(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    // 回位动画走完（动画回到 1）就交还给默认转场
    if (_phase == _BackPhase.return_ && widget.animation.value >= 1.0) {
      _phase = _BackPhase.none;
    }
    if (_phase == _BackPhase.none) {
      // 被盖住的那一页：手势进行中（以及提交后本页已变 current 但退场动画还在放）都走这条，
      // 切回默认转场会让 secondary 还是 1，画面会闪一下。
      if (!widget.route.isCurrent || predictiveBackCover.value != null) {
        return ValueListenableBuilder<double?>(
          valueListenable: predictiveBackCover,
          builder: (context, cover, _) {
            if (cover == null) return widget.fallbackTransitions;
            // 下层页在 cover 1 → 2/3 之间淡入（手势前 1/3），之后隔着顶层页的半透明 + 磨砂露出。
            final visible = 1 - ((cover - 2 / 3) / (1 / 3)).clamp(0.0, 1.0);
            final frost = _coverFrost(cover);
            final content = frost > 0.01
                ? Stack(children: [
                    widget.child,
                    // 磨砂遮罩：页面底色的半透明填充，纯色无合成层开销
                    Positioned.fill(
                      child: ColoredBox(
                          color: SemColors.bg.withValues(alpha: frost)),
                    ),
                  ])
                : widget.child;
            return Opacity(opacity: visible.clamp(0.0, 1.0), child: content);
          },
        );
      }
      return widget.fallbackTransitions;
    }
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, _) => _gestureView(context),
    );
  }

  /// 手势期间的画面：系统 progress × 屏宽 = 手指走过的距离，所以位移 1:1 跟手。
  Widget _gestureView(BuildContext context) {
    final v = widget.animation.value.clamp(0.0, 1.0); // 1 = 完整在前，0 = 已退出
    final width = MediaQuery.sizeOf(context).width;
    const dir = _dir;

    // 松手瞬间的状态（取消 / 提交后的动画都从这里插值，避免跳变）
    final released = 1 - _releaseV;
    final releaseShift = dir * released * width;
    final releaseScale = 1 - 0.05 * released;
    final releaseRadius = 16 * released;

    final double shift;
    final double opacity;
    final double scale;
    final double radius;
    switch (_phase) {
      case _BackPhase.drag:
        final gone = 1 - v;
        shift = dir * gone * width; // 1:1 跟手
        // 轻微淡出：两页叠在一起时不至于互相透得太花，也让回撤到的那页早点露出来。
        opacity = 1 - _dragFade * gone;
        scale = 1 - 0.05 * gone;
        radius = 16 * gone;
      case _BackPhase.commit:
        // 松手后继续往右滑出，在框架窗口的前 commitSpan 内滑完。
        final t = _commitT(v);
        shift = _mix(releaseShift, dir * width, t);
        // 从松手时的实际透明度继续淡出，不能从 1 拉回（否则会看到不透明度突然上升）。
        opacity = (_releaseV * (1 - t * 1.45)).clamp(0.0, 1.0);
        scale = _mix(releaseScale, 0.96, t);
        radius = _mix(releaseRadius, 12, t);
      case _BackPhase.return_:
        final span = 1 - _releaseV;
        final t = span <= 0 ? 1.0 : ((v - _releaseV) / span).clamp(0.0, 1.0);
        shift = _mix(releaseShift, 0, t);
        opacity = _mix(1 - _dragFade * released, 1, t);
        scale = _mix(releaseScale, 1, t);
        radius = _mix(releaseRadius, 0, t);
      case _BackPhase.none:
        shift = 0;
        opacity = 1;
        scale = 1;
        radius = 0;
    }

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(shift, 0),
        child: Transform.scale(
          scale: scale,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
