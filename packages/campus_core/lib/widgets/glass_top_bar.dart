import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'theme_palette.dart';

/// 顶栏里「渐变段」占顶栏高度的比例：模糊只发生在顶栏自己的范围内，
/// 上 60% 保持最强模糊，靠底部 40% 从最强线性降到 0——内容从顶栏底边露出时是清晰的。
const double kGlassBarFadeFraction = 0.4;

/// 背景（顶栏那条渐变模糊带）的最大模糊强度。**比按钮小一档**：
/// 按钮是「隔着玻璃看内容」的强模糊，背景只把穿过去的内容压淡，太强会糊成一片色块。
const double kGlassBarBlurSigma = 6;

/// 渐变模糊用几层模糊叠出来。高斯模糊可以叠加，所以把「线性衰减」拆成若干段，
/// 每段一层：越靠上的像素被越多的层糊过，累积下来就是连续增强的模糊。
/// 8 段是「看不出台阶」和「不多吃 GPU」之间的折中（4 段时肉眼能看出阶梯）。
const int _fadeBands = 8;

/// 页面第一个滚动区 / 内容的顶部内边距：躲开悬浮顶栏（状态栏 + 标题栏）。
///
/// **必须在页面 `build` 的 context（Scaffold 之上）取**：开了
/// `Scaffold.extendBodyBehindAppBar` 之后，body 里的 `MediaQuery` 已经被
/// `removePadding` 处理过——`padding.top` 清零、`viewPadding.top` 也被减到 0，
/// 在 body 内部调用会算出「只有标题栏、没有状态栏」的偏小值（内容会顶进顶栏里）。
double glassTopInset(BuildContext context, {double toolbarHeight = kToolbarHeight}) {
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
/// 模糊不能直接套 `ShaderMask` 做渐变——`ShaderMask` 会开 saveLayer，backdrop 就空了，
/// 模糊采样不到页面内容。所以这里改用叠加：把渐变段切段，每段一层 `BackdropFilter`，
/// 越靠上被越多的层糊过，累积效果就是「越靠近顶栏越模糊」。
///
/// 渐变段只占顶栏底部 [kGlassBarFadeFraction] 那一段：顶栏底边是 0（清晰），
/// 往上到渐变段起点到达最大强度，再往上是均匀的最强模糊。
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
    return LayoutBuilder(
      builder: (context, cons) {
        final h = cons.maxHeight;
        final fadeExtent = (h * fadeFraction).clamp(0.0, h);
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
    final fade = h <= 0 ? 0.6 : (fadeStart / h).clamp(0.0, 0.95);
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
