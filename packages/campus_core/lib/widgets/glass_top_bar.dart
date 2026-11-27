import 'package:flutter/material.dart';

import '../app_state.dart';
import 'theme_palette.dart';

/// 顶栏里「渐变段」占顶栏高度的比例：最上面 60% 保持较强底色，靠底部 40% 收敛到接近透明。
const double kGlassBarFadeFraction = 0.4;

/// 悬浮玻璃条（顶栏 / 底栏）的胶囊圆角：与首页底栏保持一致。
const double kGlassBarRadius = 22;

/// 悬浮玻璃底栏在按钮之外还要占掉的高度：胶囊内边距（4 × 2）+ 上下外边距（4 + 10）。
const double kGlassBottomBarChrome = 22;

/// 顶栏是否用悬浮玻璃样式（「我的 → 外观」里的开关，默认开）。
bool get glassTopBarEnabled => AppState.I.glassTopBar;

/// 页面内容顶部内边距：躲开悬浮顶栏（状态栏 + 标题栏），开关关闭时返回 0。
/// 必须在页面 build 的 context（Scaffold 之上）取，body 内的 MediaQuery 已扣过状态栏，会算小。
double glassTopInset(
  BuildContext context, {
  double toolbarHeight = kToolbarHeight,
}) {
  if (!glassTopBarEnabled) return 0;
  final mq = MediaQuery.maybeOf(context);
  return (mq?.viewPadding.top ?? 0) + toolbarHeight;
}

/// 玻璃悬浮顶栏：返回真 [AppBar]，背景换成自上而下渐隐的色带，内容从它底下穿过去。
/// 页面侧要开 `Scaffold.extendBodyBehindAppBar` 并给第一个滚动区加 [glassTopInset] 顶部留白。
PreferredSizeWidget glassAppBar(
  BuildContext context, {
  required Widget title,
  List<Widget>? actions,
  Widget? leading,
  // 全站统一：标题靠左（与 iOS / 主流安卓一致）。
  bool centerTitle = false,
  bool automaticallyImplyLeading = true,
  double toolbarHeight = kToolbarHeight,
  PreferredSizeWidget? bottom,
  double titleSpacing = NavigationToolbar.kMiddleSpacing,
}) {
  // 开关关闭：退回普通 AppBar。
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
  final autoLeading =
      automaticallyImplyLeading &&
          leading == null &&
          (ModalRoute.of(context)?.canPop ?? false)
      ? const BackButton()
      : null;
  final leadingWidget = leading ?? autoLeading;
  final appBar = AppBar(
    backgroundColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: centerTitle,
    automaticallyImplyLeading: false, // 返回键由这里自己给，才能套上圆钮样式。
    leading: leadingWidget == null ? null : _orb(leadingWidget, edge: 8),
    actions: actions
        ?.map((a) => a is IconButton ? _orb(a, edge: 3) : a)
        .toList(growable: false),
    toolbarHeight: toolbarHeight,
    titleSpacing: titleSpacing,
    title: title,
    bottom: bottom == null
        ? null
        : PreferredSize(
            preferredSize: Size.fromHeight(bottom.preferredSize.height),
            child: bottom,
          ),
  );
  // 色带包在 AppBar 外面，才能按整个顶栏高度（状态栏 + 标题栏 + bottom）铺满。
  return PreferredSize(
    preferredSize: appBar.preferredSize,
    child: Stack(
      children: [
        const Positioned.fill(child: IgnorePointer(child: GlassBarScrim())),
        Positioned.fill(child: appBar),
      ],
    ),
  );
}

/// 把标题栏里的一个按钮套成悬浮玻璃圆钮；悬浮顶栏关掉时原样返回。
Widget glassTopBarAction(Widget child, {double edge = 3}) =>
    glassTopBarEnabled ? _orb(child, edge: edge) : child;

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

/// 圆钮里的图标按钮样式：只留点击 / 图标色，背景交给外面那层玻璃。
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

/// 顶栏背景：厂商式渐变遮罩（不做实时模糊），颜色取自 [SemColors.bg]。
/// 组件是 const 实例，必须订阅 [SemColors.palette] 才能在换主题 / 切深浅色时重画。
class GlassBarScrim extends StatelessWidget {
  const GlassBarScrim({super.key, this.fadeFraction = kGlassBarFadeFraction});

  final double fadeFraction;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GlassPalette>(
      valueListenable: SemColors.palette,
      builder: (context, _, _) {
        return LayoutBuilder(
          builder: (context, _) {
            final fadeStart = (1 - fadeFraction).clamp(0.0, 1.0);
            return DecoratedBox(
              decoration: BoxDecoration(gradient: _tint(fadeStart)),
            );
          },
        );
      },
    );
  }

  /// 色带：顶部较实、向下过渡到同色透明（用同色透明而非透明黑，避免混出暗带）。
  LinearGradient _tint(double fadeStart) {
    final base = SemColors.bg;
    final solid = fadeStart.clamp(0.0, 0.95);
    // 标题中心大约在顶栏 60%~65% 处（状态栏 + 半个标题栏），实底要盖过它。
    final solidEnd = (solid + (1 - solid) * 0.45).clamp(solid, 1.0);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        base.withValues(alpha: 0.42),
        base.withValues(alpha: 0.38),
        base.withValues(alpha: 0.24),
        base.withValues(alpha: 0),
      ],
      stops: [0, solidEnd, (solidEnd + 0.12).clamp(0.0, 1.0), 1],
    );
  }
}

/// 内容顶部渐隐：在内容上叠一条与场景同色的渐变，让内容在顶栏区域逐渐溶解。
///
/// 以前用 ShaderMask(dstIn) 做真透明渐隐，但它给整块 body 加了一次 saveLayer：
/// 内容滚动 / 页面转场时每帧都要重新合成整层，是 issue #20 里转场掉帧的主要来源之一。
/// 现在改成「同色遮罩叠在内容上」：观感几乎一致（遮罩用的就是顶栏那条色带的底色），
/// 但只是一次普通渐变绘制，不进离屏图层。
class GlassFadedBody extends StatelessWidget {
  const GlassFadedBody({
    super.key,
    required this.barHeight,
    required this.child,
  });

  /// 页面在 Scaffold 之上算好的 `glassTopInset(context)`。
  final double barHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!glassTopBarEnabled || barHeight <= 0) return child;
    // 遮罩颜色随色板变化：包一层订阅，切深浅色 / 换主题时重画（页面别的部分也会重建，
    // 但这里不依赖它们顺带把自己带上——以前 const 组件不更新就是所有页面共犯）。
    return ValueListenableBuilder<GlassPalette>(
      valueListenable: SemColors.palette,
      builder: (context, palette, _) => Stack(
        children: [
          child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: SizedBox(
                // 渐隐从上沿一路连续过渡到顶栏底边下方，避免在状态栏下面出现硬边。
                height: barHeight * 1.15,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        palette.bg,
                        palette.bg.withValues(alpha: 0.86),
                        palette.bg.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.42, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部操作条是否用悬浮玻璃样式：与悬浮顶栏共用同一个开关。
bool get glassBottomBarEnabled => AppState.I.glassTopBar;

/// 滚动内容底部要让出的高度（按钮 + 胶囊外边距 + 系统手势条），开关关闭时返回 0。
/// 和 [glassTopInset] 一样必须在页面 build 的 context（Scaffold 之上）取。
double glassBottomInset(BuildContext context, {double barHeight = 44}) {
  if (!glassBottomBarEnabled) return 0;
  final mq = MediaQuery.maybeOf(context);
  final safeBottom = mq?.viewPadding.bottom ?? 0;
  return barHeight + kGlassBottomBarChrome + safeBottom;
}

/// 悬浮玻璃底栏：给 `Scaffold.bottomNavigationBar` 用的操作条（保存 / 提交这类）。
/// 页面需开 `Scaffold.extendBody`，最后一个滚动区底部留白用 [glassBottomInset]。
Widget glassBottomBar(
  BuildContext context, {
  required Widget child,
  double height = 44,
}) {
  if (!glassBottomBarEnabled) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: SizedBox(height: height, child: child),
      ),
    );
  }
  return SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Container(
        height: height + 8,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kGlassBarRadius),
          // 投影留在玻璃外面：里面那层要交给 ClipRRect 裁圆，裁完就画不出外投影了。
          boxShadow: [
            BoxShadow(
              color: SemColors.shadow,
              offset: const Offset(0, 8),
              blurRadius: 24,
            ),
          ],
        ),
        // 不做实时模糊（BackdropFilter 每帧都要把下面整块内容重新离屏采样，
        // 返回 / 前进动画期间与页面一起动就是掉帧主因，issue #20）：用与顶栏同一套
        // 渐变遮罩把下面的内容压暗，观感一致，代价只是一次普通渐变绘制。
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kGlassBarRadius),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(
                  Colors.white.withValues(alpha: 0.10),
                  SemColors.card,
                ),
                SemColors.card,
              ],
              stops: const [0, 0.5],
            ),
            border: Border.all(color: SemColors.border),
          ),
          child: child,
        ),
      ),
    ),
  );
}
