import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'theme_palette.dart';

/// 顶栏里「渐变段」占顶栏高度的比例：模糊只发生在顶栏自己的范围内，
/// 上 60% 保持最强模糊，靠底部 40% 从最强线性降到 0——内容从顶栏底边露出时是清晰的。
const double kGlassBarFadeFraction = 0.4;

/// 背景（顶栏那条渐变模糊带）的最大模糊强度。**比按钮小一档**：
/// 按钮是「隔着玻璃看内容」的强模糊，背景只把穿过去的内容压淡，太强会糊成一片色块。
const double kGlassBarBlurSigma = 8;

/// 渐变模糊用几层模糊叠出来。**层数直接等于每帧的 backdrop 采样次数**，
/// 真机上 10 层会把 GPU 打满（掉帧、快速滑动残影、低 alpha 叠层噪点），
/// 所以 P0 先压到 2 层：渐变仍然保留（1 层会变成硬边），成本降到原来的 1/5。
const int _fadeBands = 2;

/// 分段的疏密：模糊数值按 [_sigmaCurve] 变化，但切段宽度不均匀——底部清晰、
/// 相邻两级差一点就看得出来，所以底部略细、顶部略粗。取值 = 分布指数，
/// 1 = 完全等宽；越大底部越细、顶部越粗（2.0 时顶部一级跨 23%，太粗，取 1.25）。
const double _bandBias = 1.25;

/// 模糊**数值**随深度的曲线（t=0 在渐变段起点/靠顶、t=1 在顶栏底边）：
/// `sigma(t) = 最大 * (1 - t)^_sigmaCurve`。指数 > 1 即「越靠顶部变化越快、
/// 越靠底部变化越慢」。
const double _sigmaCurve = 1.8;

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

/// 玻璃悬浮顶栏：标题与按钮浮在「越往上越糊」的高斯模糊之上，内容从它底下穿过去。
///
/// 返回的仍是真 [AppBar]（不是自绘工具栏）：返回键、tooltip、状态栏图标深浅、
/// 标题居中/省略等系统行为全部保持原样，只是背景换成了渐变模糊。
/// 页面侧还要把 `Scaffold.extendBodyBehindAppBar` 打开、并给第一个滚动区加上
/// [glassTopInset] 的顶部留白，内容才会从顶栏底下穿过去而不是被压在下面。
///
/// 需要 `context` 是为了自己决定返回键：只有能 pop 的页面才给 [BackButton]，
/// 但返回键和右上角图标都要套上悬浮玻璃圆钮（框架自动加的返回键套不了样式）。
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
  final bottomHeight = bottom?.preferredSize.height ?? 0;
  final autoLeading =
      automaticallyImplyLeading &&
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
    // flexibleSpace 铺满整个顶栏（含状态栏）：渐变模糊只发生在顶栏自己的范围里，
    // 不向下延伸——内容从顶栏底边露出时已经是清晰的
    flexibleSpace: const IgnorePointer(child: GlassBarScrim()),
    bottom: bottom == null
        ? null
        : PreferredSize(
            preferredSize: Size.fromHeight(bottomHeight),
            child: bottom,
          ),
  );
}

/// 把标题栏里的一个按钮套成悬浮玻璃圆钮（40 直径、更实一档的玻璃面 + 强描边）。
/// [glassAppBar] 会自动处理 `IconButton` 类型的 action；包在 ListenableBuilder /
/// PopupMenuButton 之类结构里的按钮不会被识别，页面要显式用这个包一下。
Widget glassTopBarAction(Widget child, {double edge = 3}) => _orb(child, edge: edge);

/// 悬浮圆钮：把标题栏里的按钮套成 40 直径的玻璃圆片。
/// 圆片内不再做第二层模糊（会和顶栏的模糊层嵌套、在 Impeller 下产生椭圆光晕），
/// 改用比顶栏更实一档的玻璃面 + 强描边，读起来仍是「浮在模糊上的一块厚玻璃」。
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

/// 圆钮里的图标按钮样式：只留点击/图标色，背景交给外面那层玻璃（含模糊与描边）。
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

/// 顶栏背景：一段「上强下无」的高斯模糊 + 压在上面的底色渐变。
///
/// 模糊不能直接套 ShaderMask 做渐变——ShaderMask 会开 saveLayer，backdrop 就空了，
/// 模糊采样不到页面内容。所以这里改用叠加：把渐变段切段，每段一层 BackdropFilter，
/// 越靠上被越多的层糊过，累积效果就是「越靠近顶栏越模糊」。
///
/// 渐变段只占顶栏底部 [kGlassBarFadeFraction] 那一段：顶栏底边是 0（清晰），
/// 往上到渐变段起点到达最大强度，再往上是均匀的最强模糊。
///
/// **路由过渡期间不开模糊**：页面进场 / 退场那几帧里，下面的页面还在合成中间态
/// （甚至没有可采样的 backdrop），此时做模糊会得到一块发黑的毛玻璃；过渡结束后再开。
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
    if (anim == null) return _build(context, blur: true);
    final secondary = route?.secondaryAnimation;
    return AnimatedBuilder(
      animation: Listenable.merge([anim, secondary]),
      builder: (context, _) => _build(
        context,
        blur: _blurAllowed(anim, secondary),
      ),
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

  Widget _build(BuildContext context, {required bool blur}) {
    return LayoutBuilder(
      builder: (context, cons) {
        final h = cons.maxHeight;
        final fadeExtent = (h * fadeFraction).clamp(0.0, h);
        final fadeStart = (h - fadeExtent).clamp(0.0, h);
        final n = _fadeBands;
        // 段边界（自上而下 0→1）：模糊值本身按位置线性衰减，但**分段的宽度不均匀**——
        // t_j = 1 - (1 - j/n)^_bandBias，底部段窄（档位差一点就看得出）、顶部段宽。
        double t(int j) => 1 - math.pow(1 - j / n, _bandBias).toDouble();
        // 第 j 个段边界处的累积模糊强度：按 _sigmaCurve 的非线性曲线（顶快底慢）
        double c(int j) => sigma * math.pow(1 - t(j), _sigmaCurve).toDouble();
        final layers = <Widget>[];
        if (blur) {
          for (var k = 0; k < n; k++) {
            // 各层高斯可按「平方和」合成：本层要补的强度是 sqrt(c_k² - c_k₊₁²)
            final ck = c(k);
            final ck1 = c(k + 1);
            final s = math.sqrt(math.max(0, ck * ck - ck1 * ck1));
            if (s <= 0) continue;
            layers.add(
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: (fadeStart + fadeExtent * t(k + 1)).clamp(0.0, h),
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: s, sigmaY: s),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            );
          }
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            ...layers,
            // 底色渐变：被糊掉的内容只是色块，这层让标题和按钮在任何内容上都读得清
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: _tint(
                  fadeStart,
                  h,
                  // 过渡期没有模糊托底，色带稍微压重一点，标题依旧可读
                  boost: blur ? 1.0 : 1.35,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  LinearGradient _tint(double fadeStart, double h, {double boost = 1.0}) {
    final base = SemColors.bg;
    final fade = h <= 0 ? 0.6 : (fadeStart / h).clamp(0.0, 0.95);
    double a(double v) => (v * boost).clamp(0.0, 1.0);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        base.withValues(alpha: a(0.55)),
        base.withValues(alpha: a(0.38)),
        const Color(0x00000000),
      ],
      stops: [0, fade, 1],
    );
  }
}