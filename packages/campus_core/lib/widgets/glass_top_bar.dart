import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'theme_palette.dart';

/// 顶栏里「渐变段」占顶栏高度的比例：模糊只发生在顶栏自己的范围内，
/// 最上面 60% 保持较强模糊，靠底部 40% 逐渐收敛到接近 0——内容从顶栏底边露出时基本清晰。
const double kGlassBarFadeFraction = 0.4;

/// 顶栏模糊的最大强度（逻辑像素，最上面那条窄带）。
const double kGlassBarBlurSigma = 8;

/// 顶栏是否用悬浮玻璃样式（「我的 → 外观」里的开关，默认开）。
///
/// 页面用它决定 `Scaffold.extendBodyBehindAppBar`；[glassAppBar] 内部也看它：
/// 关掉时退回普通 [AppBar]（内容不再从顶栏底下穿过），[glassTopInset] 返回 0。
bool get glassTopBarEnabled => AppState.I.glassTopBar;

/// 页面第一个滚动区 / 内容的顶部内边距：躲开悬浮顶栏（状态栏 + 标题栏）。
/// 开关关闭时返回 0（普通 AppBar 本身占位，内容不需要额外留白）。
///
/// **必须在页面 `build` 的 context（Scaffold 之上）取**：开了
/// `Scaffold.extendBodyBehindAppBar` 之后，body 里的 `MediaQuery` 已经被
/// `removePadding` 处理过——`padding.top` 清零、`viewPadding.top` 也被减到 0，
/// 在 body 内部调用会算出「只有标题栏、没有状态栏」的偏小值（内容会顶进顶栏里）。
double glassTopInset(
  BuildContext context, {
  double toolbarHeight = kToolbarHeight,
}) {
  if (!glassTopBarEnabled) return 0;
  final mq = MediaQuery.maybeOf(context);
  return (mq?.viewPadding.top ?? 0) + toolbarHeight;
}

/// 玻璃悬浮顶栏：标题与按钮浮在「越往上越糊」的模糊之上，内容从它底下穿过去。
///
/// 返回的仍是真 [AppBar]（不是自绘工具栏）：返回键、tooltip、状态栏图标深浅、
/// 标题居中/省略等系统行为全部保持原样，只是背景换成了分层窄带模糊。
/// 页面侧还要把 `Scaffold.extendBodyBehindAppBar` 打开、并给第一个滚动区加上
/// [glassTopInset] 的顶部留白，内容才会从顶栏底下穿过去而不是被压在下面。
AppBar glassAppBar(
  BuildContext context, {
  required Widget title,
  List<Widget>? actions,
  Widget? leading,
  bool centerTitle = true,
  bool automaticallyImplyLeading = true,
  double toolbarHeight = kToolbarHeight,
  PreferredSizeWidget? bottom,
  double titleSpacing = NavigationToolbar.kMiddleSpacing,
}) {
  // 开关关闭：退回普通 AppBar（主题本身就是透明底，所以和加这个功能之前一致）
  if (!glassTopBarEnabled) {
    return AppBar(
      centerTitle: centerTitle,
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading,
      actions: actions,
      toolbarHeight: toolbarHeight,
      titleSpacing: titleSpacing,
      title: title,
      bottom: bottom,
    );
  }
  final autoLeading = automaticallyImplyLeading &&
          leading == null &&
          (ModalRoute.of(context)?.canPop ?? false)
      ? const BackButton()
      : null;
  final leadingWidget = leading ?? autoLeading;
  return AppBar(
    backgroundColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: centerTitle,
    automaticallyImplyLeading: false, // 返回键由这里自己给，才能套上圆钮样式
    leading: leadingWidget == null ? null : _orb(leadingWidget, edge: 8),
    actions: actions
        ?.map((a) => a is IconButton ? _orb(a, edge: 3) : a)
        .toList(growable: false),
    toolbarHeight: toolbarHeight,
    titleSpacing: titleSpacing,
    title: title,
    flexibleSpace: const IgnorePointer(child: GlassBarScrim()),
    bottom: bottom == null
        ? null
        : PreferredSize(
            preferredSize: Size.fromHeight(bottom.preferredSize.height),
            child: bottom,
          ),
  );
}

/// 把标题栏里的一个按钮套成悬浮玻璃圆钮（40 直径、更实一档的玻璃面 + 强描边）。
/// [glassAppBar] 会自动处理 `IconButton` 类型的 action；包在 ListenableBuilder /
/// PopupMenuButton 之类结构里的按钮不会被识别，页面要显式用这个包一下。
Widget glassTopBarAction(Widget child, {double edge = 3}) =>
    _orb(child, edge: edge);

/// 悬浮圆钮：40 直径的玻璃圆片（更实一档的玻璃面 + 细描边）。
Widget _orb(Widget child, {required double edge}) => Padding(
      padding: EdgeInsets.only(left: edge, right: edge),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: SemColors.thumb,
          shape: BoxShape.circle,
          border: Border.all(color: SemColors.borderStrong),
        ),
        child: Center(
          child: IconButtonTheme(
            data: IconButtonThemeData(style: _orbStyle()),
            child: child,
          ),
        ),
      ),
    );

/// 圆钮里的图标按钮样式：只留点击/图标色，背景交给外面那层玻璃。
ButtonStyle _orbStyle() => ButtonStyle(
      fixedSize: const WidgetStatePropertyAll(Size(40, 40)),
      minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      elevation: const WidgetStatePropertyAll(0),
      foregroundColor: WidgetStatePropertyAll(SemColors.textPrimary),
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      shape: const WidgetStatePropertyAll(CircleBorder()),
    );

/// 顶栏背景：**3 条边缘窄带模糊** + 压在上面的底色渐变。
///
/// 为什么不是整条栏的实时模糊：Flutter/Impeller 里大面积、多层、或者图层原点带小数的
/// `BackdropFilter` 在滚动时会跨帧采样/抖动（上游 #138615、#194846），表现为内容在玻璃
/// 下面重影、跳动。Apple 系统 App 的可复刻做法（BlurUIKit / onejs）也是「沿边缘叠
/// 几条窄带模糊」，只糊边缘、成本低、不需要大面积实时重采样。
///
/// 实现：从下往上叠 3 条越来越高的模糊带（sigma 逐条增大），后画的层能采到先前层的
/// 输出，累积后越靠上越糊、最底边接近清晰；所有矩形的 y 都对齐到**整数物理像素**，
/// 规避 Impeller「小数原点导致内容偏移 1px」的问题。
/// 路由过渡帧（没有稳定 backdrop）不画模糊，只画色带。
class GlassBarScrim extends StatelessWidget {
  const GlassBarScrim({
    super.key,
    this.fadeFraction = kGlassBarFadeFraction,
    this.sigma = kGlassBarBlurSigma,
  });

  final double fadeFraction;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final anim = route?.animation;
    final secondary = route?.secondaryAnimation;
    if (anim == null) return _build(context, blur: true, boost: 1.0);
    return AnimatedBuilder(
      animation: Listenable.merge([anim, secondary]),
      builder: (context, _) {
        final routeOk = _blurAllowed(anim, secondary);
        return _build(context, blur: routeOk, boost: routeOk ? 1.0 : 1.35);
      },
    );
  }

  /// 路由动画没跑完（进场 / 退场 / 被新页面压住的过渡帧）就不做模糊。
  static bool _blurAllowed(
    Animation<double>? primary,
    Animation<double>? secondary,
  ) {
    final primaryDone = primary == null ||
        primary.status == AnimationStatus.completed ||
        primary.status == AnimationStatus.dismissed;
    final secondaryIdle = secondary == null ||
        secondary.status == AnimationStatus.dismissed ||
        secondary.status == AnimationStatus.completed;
    return primaryDone && secondaryIdle;
  }

  Widget _build(
    BuildContext context, {
    required bool blur,
    required double boost,
  }) {
    return LayoutBuilder(
      builder: (context, cons) {
        final h = cons.maxHeight;
        final w = cons.maxWidth;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final fadeStart = (1 - fadeFraction).clamp(0.0, 1.0);
        final strips = blur ? _strips(w, h, dpr, fadeStart) : const <Widget>[];
        return Stack(
          fit: StackFit.expand,
          children: [
            ...strips,
            // 底色渐变：被糊掉的内容只是色块，这层让标题和按钮在任何内容上都读得清。
            // 末段必须是「同色透明」而不是透明黑，否则线性插值会在中间混出一条暗带。
            DecoratedBox(
              decoration: BoxDecoration(gradient: _tint(fadeStart, boost: boost)),
            ),
          ],
        );
      },
    );
  }

  /// 3 条窄带：越靠上的带越高、sigma 越大；底边那条 sigma 很小（近似清晰）。
  /// 所有 y 坐标对齐到整数物理像素。
  List<Widget> _strips(double w, double h, double dpr, double fadeStart) {
    // 每条带从顶栏顶部延伸到 bottomF（占顶栏高度的比例）；从下往上 sigma 递增。
    final bottoms = <double>[
      1.0, // 整条顶栏（最下面一层，sigma 最小）
      (fadeStart + (1 - fadeStart) * 0.55).clamp(0.0, 1.0),
      fadeStart, // 最上面一层：到渐变段起点为止（最强）
    ];
    final maxSigma = sigma * dpr; // 物理像素
    final sigmas = <double>[
      maxSigma * 0.15, // 底边附近：几乎清晰
      maxSigma * 0.45,
      maxSigma * 0.8,
    ];
    // 累积后最上层的等效 sigma ≈ sqrt(0.15²+0.45²+0.8²)·max ≈ 0.93·max
    final widgets = <Widget>[];
    for (var i = 0; i < bottoms.length; i++) {
      final bottom = _alignPx(bottoms[i] * h, dpr);
      if (bottom <= 0) continue;
      final s = sigmas[i] / dpr; // 转回逻辑像素
      widgets.add(
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: bottom,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: s, sigmaY: s),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  /// 把逻辑尺寸对齐到整数物理像素，避免图层原点带小数（Impeller #194846）。
  static double _alignPx(double logical, double dpr) =>
      (logical * dpr).roundToDouble() / dpr;

  LinearGradient _tint(double fadeStart, {double boost = 1.0}) {
    final base = SemColors.bg;
    final fade = fadeStart.clamp(0.0, 0.95);
    double a(double v) => (v * boost).clamp(0.0, 1.0);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        base.withValues(alpha: a(0.55)),
        base.withValues(alpha: a(0.38)),
        base.withValues(alpha: 0),
      ],
      stops: [0, fade, 1],
    );
  }
}
