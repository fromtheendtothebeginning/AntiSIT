import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'theme_palette.dart';

/// 悬浮玻璃顶栏向下的「渐变模糊」过渡段高度：模糊从标题栏下沿开始，
/// 由最强（[kGlassBarBlurSigma]）线性衰减到 0——内容往顶栏滚的途中被逐级糊掉。
const double kGlassBarFadeExtent = 44;

/// 背景（顶栏那条渐变模糊带）的最大模糊强度。**比按钮小一档**：
/// 按钮是「隔着玻璃看内容」的强模糊，背景只把穿过去的内容压淡，太强会糊成一片色块。
const double kGlassBarBlurSigma = 10;

/// 按钮（悬浮圆钮）的模糊强度：不做渐变，直接复用玻璃底栏那一档（sigma 12）。
const double kGlassOrbBlurSigma = 12;

/// 渐变模糊用几层模糊叠出来。高斯模糊可以叠加，所以把「线性衰减」拆成若干段，
/// 每段一层：越靠上的像素被越多的层糊过，累积下来就是连续增强的模糊。
/// 层数越多过渡越顺，代价是每帧多几次 backdrop 采样——先取 4，卡再减。
const int _fadeBands = 4;

/// 顶栏（状态栏 + 标题栏 + 渐变模糊段）的总高度。
double glassBarHeight(BuildContext context, {double toolbarHeight = kToolbarHeight}) =>
    MediaQuery.viewPaddingOf(context).top + toolbarHeight + kGlassBarFadeExtent;

/// 页面第一个滚动区 / 内容的顶部内边距：躲开悬浮顶栏和它下方那段渐变模糊。
///
/// 注意必须用 `viewPadding`：开了 `Scaffold.extendBodyBehindAppBar` 之后 body 里的
/// `MediaQuery.padding.top` 会被清零，用 `paddingOf` 会算出 0。
double glassTopInset(BuildContext context, {double toolbarHeight = kToolbarHeight}) =>
    glassBarHeight(context, toolbarHeight: toolbarHeight);

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
  final bottomHeight = bottom?.preferredSize.height ?? 0;
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
    // flexibleSpace 铺满整个顶栏（含状态栏和下方那段渐变），模糊层借此延伸到标题栏之外；
    // bottom 只用「留出高度」来给渐变段腾地方，本身不画东西
    flexibleSpace: const IgnorePointer(child: GlassBarScrim()),
    bottom: PreferredSize(
      preferredSize: Size.fromHeight(bottomHeight + kGlassBarFadeExtent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (bottom != null) SizedBox(height: bottomHeight, child: bottom),
          const SizedBox(height: kGlassBarFadeExtent),
        ],
      ),
    ),
  );
}

/// 悬浮圆钮：把标题栏里的按钮套成 40 直径的玻璃圆片。
/// 圆片内部自己做一层**均匀**模糊（[kGlassOrbBlurSigma]，与玻璃底栏同档、不做渐变），
/// 再压半透明卡面 + 细描边——按钮的糊度因此始终比背后的背景渐变带更强。
Widget _orb(Widget child, {required double edge}) => Padding(
      padding: EdgeInsets.only(left: edge, right: edge),
      child: SizedBox(
        width: 40,
        height: 40,
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: kGlassOrbBlurSigma,
                  sigmaY: kGlassOrbBlurSigma,
                ),
                child: const SizedBox.expand(),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: SemColors.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: SemColors.border),
                  ),
                ),
              ),
              Center(
                child: IconButtonTheme(
                  data: IconButtonThemeData(style: _orbStyle()),
                  child: child,
                ),
              ),
            ],
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
/// 模糊不能直接套 `ShaderMask` 做渐变——`ShaderMask` 会开 saveLayer，backdrop 就空了，
/// 模糊采样不到页面内容。所以这里改用叠加：把渐变段切段，每段一层 `BackdropFilter`，
/// 越靠上被越多的层糊过，累积效果就是「越靠近顶栏越模糊」。
class GlassBarScrim extends StatelessWidget {
  const GlassBarScrim({
    super.key,
    this.fadeExtent = kGlassBarFadeExtent,
    this.sigma = kGlassBarBlurSigma,
  });

  final double fadeExtent;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        final h = cons.maxHeight;
        final fadeStart = (h - fadeExtent).clamp(0.0, h);
        final n = _fadeBands;
        final layers = <Widget>[];
        for (var k = 0; k < n; k++) {
          // 叠加公式：第 k 段的累积强度是 c_k = sigma * (1 - k/n)，
          // 而各层的高斯可以按「平方和」合成，所以本层要补的强度是 sqrt(c_k² - c_k₊₁²)
          final ck = sigma * (1 - k / n);
          final ck1 = sigma * (1 - (k + 1) / n);
          final s = math.sqrt(math.max(0, ck * ck - ck1 * ck1));
          if (s <= 0) continue;
          layers.add(Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: (fadeStart + fadeExtent * (k + 1) / n).clamp(0.0, h),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: s, sigmaY: s),
                child: const SizedBox.expand(),
              ),
            ),
          ));
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            ...layers,
            // 底色渐变：被糊掉的内容只是色块，这层让标题和按钮在任何内容上都读得清
            DecoratedBox(
              decoration: BoxDecoration(gradient: _tint(fadeStart, h)),
            ),
          ],
        );
      },
    );
  }

  LinearGradient _tint(double fadeStart, double h) {
    final base = SemColors.bg;
    final fade = h <= 0 ? 0.5 : (fadeStart / h).clamp(0.0, 0.95);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        base.withValues(alpha: 0.55),
        base.withValues(alpha: 0.38),
        base.withValues(alpha: 0),
      ],
      stops: [0, fade, 1],
    );
  }
}
