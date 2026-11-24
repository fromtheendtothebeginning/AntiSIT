import 'package:campus_core/campus_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// 预测式返回的**旧样式**：整页淡化 + 轻微缩小 + 圆角滑出，露出下层页。
///
/// 与「位移 + 压暗」新样式并列，由外观设置里的样式选择器决定用哪一套
/// （见 [PredictiveBackStyle]）。这套的实现要点：
///
/// * 拖动：当前页 1:1 跟手往右移，同时按进度淡化、缩小、加圆角；
/// * 下层页：手势前 1/3 就淡入到位，并在前 2/3 隔着「磨砂遮罩」渐进变清楚
///   （纯色填充而不是全屏高斯模糊：零合成层开销，观感一致）；
/// * 松手：提交从松手位置继续滑出并淡出；取消从松手位置滑回原位，两段都连续不跳。
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

/// 返回手势所处的阶段（决定画面由谁驱动）。
enum _BackPhase {
  /// 没参与这次手势：普通导航，走默认转场。
  none,

  /// 手指还在屏幕上：位移 1:1 跟手。
  drag,

  /// 松手提交：从松手位置继续滑出屏幕并淡出。
  commit,

  /// 松手取消：从松手位置滑回原位。
  return_,
}

/// 预测式返回手势期间的「覆盖率」（1 = 顶层页全盖住下层页，0 = 已滑走；
/// null = 没有手势在进行）。被盖住的页据此做**渐进磨砂**：
/// 手势前 1/3 隔着重磨砂，1/3 → 2/3 之间线性变清楚（插值），之后完全清晰。
/// 拖动时它就是顶层页的动画值；提交后按实际滑出进度提前归零（见 [_commitT]）。
final ValueNotifier<double?> predictiveBackCover = ValueNotifier<double?>(null);

/// 覆盖进度 → 下层页的磨砂遮罩不透明度（0..0.45）。手势进度 g = 1 - v：
/// g ≤ 1/3 时最「糊」（下层刚要露面），1/3 → 2/3 线性减到 0，之后不再磨砂。
///
/// **为什么是遮罩不是高斯模糊**：全屏 ImageFiltered 逐帧 saveLayer，
/// 中低端机收尾掉帧、滤镜卸载时还会跳一帧（实测「最后卡顿一下、割裂」）；
/// 磨砂遮罩是纯色填充，零合成层开销，观感同为「隔着一层看不清」。
double _coverFrost(double v) =>
    0.45 * (1 - (((1 - v) - 1 / 3) / (1 / 3)).clamp(0.0, 1.0));

class _PredictiveFadeBackGestureState extends State<PredictiveFadeBackGesture>
    with WidgetsBindingObserver {
  /// 一律按「从左边返回」那套走：不论手指从哪条边划进来，当前页都往右滑出、
  /// 上一页从左面露出来（用户要求：不跟着手势边换方向）。
  static const double _dir = 1;

  /// 拖动期间当前页最多淡掉多少：1.0 = 进度 1/3 时顶层页只剩 67% 不透明度。
  static const double _dragFade = 1.0;

  _BackPhase _phase = _BackPhase.none;

  /// 松手那一刻的动画值（= 1 - 手势进度）。提交 / 取消后的动画都从它续上，
  /// 保证松手前后画面的位移、缩放是连续的，不会跳。
  double _releaseV = 1;

  /// 提交后 controller 反弹到的最大值（正常就是 1.0，见 [_commitT]）。
  double _commitFrom = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 手势期间把覆盖率发布给被盖住的页（渐进磨砂 / 揭露用）。
    // 动画监听在帧调度阶段触发，不在 build 里改 ValueNotifier（会撞上 build 期重建）。
    widget.animation.addListener(_publishCover);
  }

  void _publishCover() {
    if (_phase == _BackPhase.none) return;
    final v = widget.animation.value.clamp(0.0, 1.0);
    final done = (_phase == _BackPhase.return_ && v >= 1.0) ||
        (_phase == _BackPhase.commit && v <= 0.0);
    if (done) {
      predictiveBackCover.value = null;
    } else if (_phase == _BackPhase.commit) {
      if (v > _commitFrom) _commitFrom = v;
      // 下层页的揭露按「实际滑出进度」（1 - 位移/屏宽）走：等于拖动时的 v，
      // 提交后又跟着加快后的滑出一起归零。框架把动画值拉回 1.0 的那一跳
      // 不能外漏——漏出去下层页会先瞬间消失再罩上磨砂，闪一下。
      predictiveBackCover.value = _releaseV * (1 - _commitT(v));
    } else {
      predictiveBackCover.value = v;
    }
  }

  /// 提交后滑出的进度（0 = 刚松手，1 = 滑完）：起点取 [_commitFrom]——
  /// 框架提交时把 controller 拉回 1.0，它就是 1.0；若哪天框架改成从松手值
  /// 反向，起点自然是松手值，公式同样从 0 起算。只用窗口前 commitSpan 走完。
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

  // ===== WidgetsBindingObserver：接管系统返回手势，其余交给 Flutter 自己的路由实现 =====

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    // 按键返回不接管；不能返回的页（首页 / 被压住的页）也返回 false，
    // 让事件继续往后传——观察者按注册顺序通知，只有当前那一页该接。
    // 「预测式返回动画」关掉时同样不接管：框架对没人接的手势会在松手提交时
    // 按普通返回 pop，手势期间画面不动。
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
    // 兜底收尾：拖回起点才松手时动画值已经是 1.0，框架不会再跑回位动画、
    // 动画通知也就不会再来——覆盖率会停在被盖时那个旧值上。之后这页（或被盖的
    // 那一页）一旦成为当前页，就会按「被盖住」渲染成全透明，用户看到的是空白界面。
    _publishCover();
  }

  @override
  void handleCommitBackGesture() {
    _releaseV = widget.animation.value;
    _commitFrom = 0;
    // 相位要先切：route.handleCommitBackGesture() 内部会把动画值拉回 1.0，
    // 那一跳会同步通知 [_publishCover]，相位还是 drag 的话会被当成拖动值发布。
    if (mounted) setState(() => _phase = _BackPhase.commit);
    widget.route.handleCommitBackGesture();
    // 兜底收尾：松手时动画值已经在终点（拖到底才松手）时框架不会再跑动画，
    // 通知也不会再来一次，覆盖率就得在这里自己清掉。
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
      // 被盖住的页：预测式返回手势的另一面。手势进行中（cover 非 null）
      // 下层页在**手势前 1/3** 就淡入到位并按覆盖进度模糊——旧曲线要到手势走完
      // 约 2/3 才开始出现，用户实测「1/3 时完全看不到」。
      //
      // 「手势还在进行」也要走这条：提交后本页立刻变成 current（route 已被 pop），
      // 但手势的退场动画还在放。若此刻切回默认转场曲线，secondary 还是 1
      // （被盖住的起点）→ 该曲线直接给整页不可见，画面会闪一下（实测有）。
      if (!widget.route.isCurrent || predictiveBackCover.value != null) {
        return ValueListenableBuilder<double?>(
          valueListenable: predictiveBackCover,
          builder: (context, cover, _) {
            if (cover == null) return widget.fallbackTransitions;
            // 覆盖率 cover（1 = 全盖住，0 = 已滑走）。
            // 下层页透明度：cover 1 → 2/3 之间淡入（手势前 1/3），之后保持全可见，
            // 隔着顶层页的半透明 + 磨砂露出；磨砂同前：前 1/3 最重，1/3 → 2/3 变清楚。
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

  /// 手势期间的画面。关键是位移：系统给的 progress 就是「手指从边缘走到对边的比例」，
  /// 乘上屏宽即手指走过的距离，所以进度 × 屏宽 = 1:1 跟手。
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
        // 轻微淡出：玻璃页半透明，两页叠在一起时不至于互相透得太花；
        // 也让「回撤到的那一页」早点露出来。
        opacity = 1 - _dragFade * gone;
        scale = 1 - 0.05 * gone;
        radius = 16 * gone;
      case _BackPhase.commit:
        // 松手后继续往右滑出去：一松手就走，并在框架窗口的前 commitSpan 内滑完。
        final t = _commitT(v);
        shift = _mix(releaseShift, dir * width, t);
        // 从松手那一刻的实际透明度（= _releaseV）继续淡出，不能从 1 拉回：
        // 拖得深时松手页面已接近全透明，跳回 1 用户会看到「不透明度突然上升」。
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
