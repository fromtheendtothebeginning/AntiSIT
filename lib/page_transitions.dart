import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:campus_core/campus_core.dart';

import 'predictive_back_fade.dart';

/// 顶层路由是不是页面（[PageRoute]）：只有页面盖页面时才搬动旧页。
///
/// 弹窗 / 菜单 / 底部菜单同样会驱动被盖页的 secondaryAnimation，必须靠它过滤。
final ValueNotifier<bool> topRouteIsPage = ValueNotifier<bool>(true);

/// 跟踪顶层路由类型，结果写进 [topRouteIsPage]。
class TopRouteKindObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      topRouteIsPage.value = route is PageRoute;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      topRouteIsPage.value = previousRoute is PageRoute;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      topRouteIsPage.value = newRoute is PageRoute;
}

/// 前进 / 返回的整页位移转场：新页整块滑入滑出，旧页左移并轻微压暗。
///
/// 实现约束：
/// * 上层页要垫一张与全局场景底一致的底（本 App 页面半透明，否则滑入时透出下层页）；
/// * 不能用 SlideTransition / FractionalTranslation（其 `applyPaintTransform` 读
///   `child.size`，弹窗 localToGlobal 时会抛断言）；
/// * 只有 [PageRoute] 盖上来才搬旧页，见 [topRouteIsPage]。
class SlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const SlidePageTransitionsBuilder();

  /// 旧页被推走的距离（屏宽比例）。
  static const double oldShift = 0.20;

  /// 旧页最深压暗（只用来拉开层次）。
  static const double oldDim = 0.10;

  /// 前进时长。
  static const Duration pushDuration = Duration(milliseconds: 520);

  /// 返回时长。
  ///
  /// 比原先的 320ms 短：返回是「回到刚才」的动作，拖沓会显得迟钝。
  /// 320 → 400 是把时长拉长来摊薄单帧位移，但曲线放缓后单帧位移本身已经降下来
  /// （见 [_popCurve]），再拖长就只是慢。取 320ms 的 0.94 倍 = 300ms，
  /// 单帧位移与原先持平，观感明显更利索。
  static const Duration popDuration = Duration(milliseconds: 300);

  @override
  Duration get transitionDuration => pushDuration;

  @override
  Duration get reverseTransitionDuration => popDuration;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    // 首屏也包一层：进场动画值已是 1（不位移），但被上层页覆盖时要跟着左移变暗。
    return _SlidePageTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// 前进缓动：起步即走、末尾缓慢收住。
///
/// 不要用极端 expo-out（如 `Cubic(0.16, 1, 0.3, 1)`）：25% 时长走完一半以上，
/// 观感是「旧页闪一下就被盖住，后面几乎不动」。
///
/// 这里比原来缓一档：原先 `Cubic(0.20, 0.85, 0.20, 1.0)` 25% 时长就走完 79%
/// （峰值速度 4.3 倍平均速度），顶页单帧要横move 149px（1080 宽下 13.8% 屏宽），
/// 掉一帧就是肉眼可见的跳。现在 25% 走 55%、峰值 2.3 倍，配合下面的「两层同步」，
/// 前进看起来是一整块平移而不是「闪一下」。
const Curve _pushCurve = Cubic(0.30, 0.60, 0.30, 1.0);

/// 返回缓动：起步柔和、全程匀速感更强。
///
/// 原先是 `Cubic(0.30, 0.55, 0.35, 1.0)`，25% 时长就走完一半路程（峰值速度是
/// 平均速度的 2.1 倍）——返回时像被「弹」回去。改成 25% 只走 39%、峰值 1.8 倍，
/// 也就是 issue #16 要求的「调整速度曲线使曲线变缓」。
///
/// 预告式返回手势的反解（[_PredictiveOrFadeThroughState._routeProgress]）读的也是
/// 这条曲线，改这里跟手位移会自动跟着变。
const Curve _popCurve = Cubic(0.35, 0.42, 0.40, 1.0);

/// 前进时被盖住的旧页该不该按「前进节奏」走。
///
/// 前进时下层要从 0 退到 -20%。原先它延后 22% 才开始动、且用 Interval 截断，
/// 结果是：顶页已经滑过大半屏，下层才刚起步，最后 22% 下层又完全静止——
/// 两层各走一套节奏，观感是「上层飞进来、下层才慢吞吞让开」，也就是前进方向的
/// 不同步（和返回那个卡顿是同一个病根，只是方向相反）。
///
/// 现在前进 / 返回都让两层共用同一条曲线：下层用 [_pushCurve] / [_popCurve] 正放，
/// 顶页用同一条反向，速度比恒为 `oldShift`（20%），看起来是整块一起平移。
bool _isReturning(Animation<double> secondaryAnimation) =>
    predictiveBackGesturing ||
    secondaryAnimation.status == AnimationStatus.reverse;

/// 预测式返回手势是否进行中（含松手后的收尾动画）。
///
/// 拖动时 controller 的 value 是被直接赋值的、状态停在 completed，只看状态会被误判成
/// 「前进」；这里用手势标记兜住，同时保证松手收尾与拖动阶段用同一条缓动。
bool predictiveBackGesturing = false;

/// 按动画方向取缓动：前进用陡的，返回 / 预测式手势用缓的。
Curve _curveFor(Animation<double> a) =>
    (a.status == AnimationStatus.reverse || predictiveBackGesturing)
        ? _popCurve
        : _pushCurve;

/// 单个页面的转场绘制：位移 + 转场期间垫场景底 + 旧页压暗。
class _SlidePageTransition extends StatelessWidget {
  const _SlidePageTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation, topRouteIsPage]),
      child: child,
      builder: (context, child) {
        final width = MediaQuery.sizeOf(context).width;
        final covered = topRouteIsPage.value && secondaryAnimation.value > 0.001;

        double shift;
        double dim;
        if (covered) {
          // 被上层页推走：前进 0 → -20%，返回 -20% → 0（同一公式，动画值反向）。
          //
          // 前进和返回都跟顶页共用同一条曲线（各用自己方向那条），两层位移速度比
          // 恒为 oldShift，整体像一块板平移。以前前进是「延后 22% + Interval 截断」，
          // 会造成上层已经滑过大半、下层才刚起步，最后一段下层又静止。
          final s = (_isReturning(secondaryAnimation) ? _popCurve : _pushCurve)
              .transform(secondaryAnimation.value);
          shift = -SlidePageTransitionsBuilder.oldShift * width * s;
          dim = SlidePageTransitionsBuilder.oldDim * s;
        } else {
          // 自己进出：前进从右侧滑到 0，返回从 0 滑出到右侧。
          final c = _curveFor(animation).transform(animation.value);
          shift = (1 - c) * width;
          dim = 0;
        }

        // 转场期间给页面垫一张场景底（静止时透明）。判断必须看**动画状态**而不是数值：
        // 返回第一帧 value 还是 1，按数值判断会漏垫一帧，透出下层页形成闪烁。
        final busy = animation.status == AnimationStatus.forward ||
            animation.status == AnimationStatus.reverse ||
            (topRouteIsPage.value &&
                (secondaryAnimation.status == AnimationStatus.forward ||
                    secondaryAnimation.status == AnimationStatus.reverse));

        return Transform.translate(
          offset: Offset(shift, 0),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              // 场景底（常驻组件树，只改显隐与透明度，不触发布局）
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: busy ? 1 : 0,
                    child: GlassScenePaint(wells: GlassScene.wells),
                  ),
                ),
              ),
              child!,
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000).withValues(alpha: dim),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 安卓转场：**系统返回手势**（Android 14+ 预测式返回）交给官方
/// [PredictiveBackPageTransitionsBuilder] 的跟手逻辑，普通前进 / 返回仍走
/// [SlidePageTransitionsBuilder]。
///
/// 不能直接用官方 builder 兜底：它在非手势导航时会回落到横向滑动的
/// FadeForwardsPageTransitionsBuilder，换掉这里的淡入淡出观感。
class PredictiveOrFadeThroughBuilder extends PageTransitionsBuilder {
  const PredictiveOrFadeThroughBuilder();

  /// 路由过渡时长取的是「当前平台 builder」的值，安卓这条链走本类，
  /// 所以时长要在这里同步，否则改 [SlidePageTransitionsBuilder] 的时长对安卓不生效。
  @override
  Duration get transitionDuration => SlidePageTransitionsBuilder.pushDuration;

  @override
  Duration get reverseTransitionDuration => SlidePageTransitionsBuilder.popDuration;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    // 监听 AppState：外观设置里切换「预测式返回样式」后立刻生效。
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final transitions = const SlidePageTransitionsBuilder().buildTransitions(
            route, context, animation, secondaryAnimation, child);
        if (AppState.I.predictiveBackStyle == PredictiveBackStyle.fade) {
          // 旧样式：整页淡化 + 缩小 + 圆角滑出。
          return PredictiveFadeBackGesture(
            route: route,
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            fallbackTransitions: transitions,
            commitSpan: (180 /
                    SlidePageTransitionsBuilder.popDuration.inMilliseconds)
                .clamp(0.15, 1.0),
            child: child,
          );
        }
        return _PredictiveOrFadeThrough(
          route: route,
          animation: animation,
          child: transitions,
        );
      },
    );
  }
}

/// 预测式返回：把系统手势进度换算成路由动画值，画面复用默认返回动画。
///
/// * 跟手线性：手势进度先乘 [_gain] 放大，再反解返回曲线成动画值，渲染仍走同一条
///   曲线，位移与手指位移保持固定倍数；
/// * 松手后不重播：让路由从当前位置反向播完。
class _PredictiveOrFadeThrough extends StatefulWidget {
  const _PredictiveOrFadeThrough({
    required this.route,
    required this.animation,
    required this.child,
  });

  final PageRoute<dynamic> route;
  final Animation<double> animation;
  final Widget child;

  @override
  State<_PredictiveOrFadeThrough> createState() => _PredictiveOrFadeThroughState();
}

class _PredictiveOrFadeThroughState extends State<_PredictiveOrFadeThrough>
    with WidgetsBindingObserver {
  /// 手势位移 → 页面进度的放大倍数：划过半个屏宽即走完全程。
  static const double _gain = 2.0;

  /// 把系统手势进度换算成路由动画值：`value = popCurve⁻¹(1 - 进度 × [_gain])`。
  static double _routeProgress(double gestureProgress) {
    final advanced = (gestureProgress * _gain).clamp(0.0, 1.0);
    return _invertCurve(_popCurve, 1 - advanced);
  }

  /// 单调曲线的数值反解（二分）：返回 x 使 `curve.transform(x) ≈ y`。
  static double _invertCurve(Curve curve, double y) {
    if (y <= 0) return 0;
    if (y >= 1) return 1;
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 30; i++) {
      final mid = (lo + hi) / 2;
      if (curve.transform(mid) < y) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  /// 框架正在跑收尾动画（跑完清掉手势标记）。
  bool _settling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.animation.addListener(_onAnimationTick);
  }

  @override
  void dispose() {
    widget.animation.removeListener(_onAnimationTick);
    WidgetsBinding.instance.removeObserver(this);
    predictiveBackGesturing = false;
    super.dispose();
  }

  /// 收尾动画播完后清除手势标记。
  void _onAnimationTick() {
    if (!_settling) return;
    if (!widget.animation.isAnimating) {
      _settling = false;
      predictiveBackGesturing = false;
    }
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    // 按键返回、不能返回的页、关闭了预测式返回时都不接管，让事件继续往后传。
    if (backEvent.isButtonEvent ||
        !AppState.I.predictiveBack ||
        !widget.route.isCurrent ||
        !widget.route.popGestureEnabled) {
      return false;
    }
    predictiveBackGesturing = true;
    widget.route.handleStartBackGesture(
        progress: _routeProgress(backEvent.progress));
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) =>
      widget.route.handleUpdateBackGestureProgress(
          progress: _routeProgress(backEvent.progress));

  @override
  void handleCancelBackGesture() {
    _settling = true;
    // 取消：从当前位置正播回 1（框架内部 forward，不吃掉已有进度）。
    widget.route.handleCancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    _settling = true;
    // 提交：**不能**调 route.handleCommitBackGesture()，它内部先 pop() 再
    // reverse(from: upperBound)，等于从头重播一遍。直接 pop，让 didPop 自己 reverse。
    final nav = widget.route.navigator;
    nav?.pop();
    // 补上框架 _handleDragEnd 的收尾记账，否则 Navigator.userGestureInProgress 一直是
    // true，真机上表现为「返回动画结束后整屏点不动」（按键仍可用）。
    late final AnimationStatusListener stopGesture;
    stopGesture = (AnimationStatus status) {
      widget.animation.removeStatusListener(stopGesture);
      nav?.didStopUserGesture();
    };
    if (widget.animation.status == AnimationStatus.dismissed) {
      // 已拖到底、pop 当场完成，不会再有一次状态变化
      nav?.didStopUserGesture();
    } else {
      widget.animation.addStatusListener(stopGesture);
    }
  }

  /// 画面完全交给默认转场，这里只透传。
  @override
  Widget build(BuildContext context) => widget.child;
}
