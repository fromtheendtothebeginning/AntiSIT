import 'package:flutter/material.dart';

import '../app_state.dart';
import 'theme_palette.dart';

/// 顶栏里「渐变段」占顶栏高度的比例：模糊只发生在顶栏自己的范围内，
/// 最上面 60% 保持较强模糊，靠底部 40% 逐渐收敛到接近 0——内容从顶栏底边露出时基本清晰。
const double kGlassBarFadeFraction = 0.4;


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
PreferredSizeWidget glassAppBar(
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
  final appBar = AppBar(
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
    bottom: bottom == null
        ? null
        : PreferredSize(
            preferredSize: Size.fromHeight(bottom.preferredSize.height),
            child: bottom,
          ),
  );
  // AppBar 自己把 flexibleSpace 放在 SafeArea 里面，状态栏那一条不会被盖住；
  // 这里把色带包在 AppBar 外面、按整个顶栏高度（状态栏 + 标题栏 + bottom）铺满。
  return PreferredSize(
    preferredSize: appBar.preferredSize,
    child: Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(child: GlassBarScrim()),
        ),
        Positioned.fill(child: appBar),
      ],
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

/// 顶栏背景：**厂商式渐变遮罩（scrim）**——不做任何实时模糊。
///
/// 依据（各家系统软件的实际做法）：
/// * Android/AOSP 的真模糊是「系统合成器窗口模糊」（只糊窗口背后，糊不到 App 自己的内容），
///   弱 GPU 设备直接不支持；OEM（HyperOS/ColorOS/One UI）在中端机上就只留这种色带。
/// * iOS 的 UIVisualEffectView 不能加渐变遮罩，系统栏在滚动到顶时也是不透明背景。
/// * Flutter 上游的实时 backdrop 在滚动中还有跨帧采样/小数原点偏移问题
///   （#138615 / #194846），这正是之前重影与噪点的来源。
///
/// 所以这里只画一层「自上而下由实到透」的底色渐变：内容从顶栏底下穿过时是**淡出**
/// 而不是被糊——没有 backdrop 捕获，滚动/overscroll/切页都不可能出重影、噪点或掉帧。
class GlassBarScrim extends StatelessWidget {
  const GlassBarScrim({
    super.key,
    this.fadeFraction = kGlassBarFadeFraction,
  });

  final double fadeFraction;

  @override
  Widget build(BuildContext context) {
    // 色带颜色取自 SemColors.bg。AppBar 里的这层是 const 组件，
    // 页面重建时 Flutter 会跳过它（同一个 const 实例），所以在应用内换主题 / 切深浅色
    // 时它不会跟着变，必须重启才生效。这里订阅色板通知，色板一换就重画。
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

  /// 厂商式色带：标题/状态栏那一带保持「较实」的底色（内容滚到标题后面也读得清），
  /// 只在顶栏最下面约 1/3 快速过渡到完全透明。
  /// 末段用「同色透明」而不是透明黑——RGBA 线性插值到透明黑会混出暗带。
  LinearGradient _tint(double fadeStart) {
    final base = SemColors.bg;
    final solid = fadeStart.clamp(0.0, 0.95);
    // 标题中心大约在顶栏 60%~65% 处（状态栏 + 半个标题栏），实底要盖过它
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
/// 内容顶部渐隐：给页面 body 套一层 alpha 渐变，让内容在顶栏区域逐渐透明。
/// 和顶栏色带（盖一层同色）叠加：色带负责"压低对比度"，这层负责"内容自己溶解"。
///
/// [barHeight] 传页面在 Scaffold 之上算好的 glassTopInset(context)。
class GlassFadedBody extends StatelessWidget {
  const GlassFadedBody({
    super.key,
    required this.barHeight,
    required this.child,
  });

  final double barHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!glassTopBarEnabled || barHeight <= 0) return child;
    return LayoutBuilder(
      builder: (context, cons) {
        final h = cons.maxHeight;
        if (!h.isFinite || h <= 0) return child;
        // 渐隐从上沿（状态栏顶部）就开始，一路过渡到顶栏底边再往下一点：
        // 之前是「前 55% 全透明 → 45% 内渐变」，渐变的起止都落在顶栏内部，
        // 看起来像在状态栏下面被切了一刀。现在整段都是连续过渡，没有硬边。
        final end = ((barHeight * 1.15) / h).clamp(0.0, 1.0);
        final mid = ((barHeight * 0.45) / h).clamp(0.0, end);
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0x00000000),
              Color(0x22000000),
              Color(0xFFFFFFFF),
              Color(0xFFFFFFFF),
            ],
            stops: [0, mid, end, 1],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}