import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../pages/connect_page.dart';

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

/// 统一错误处理：snackbar 提示；401 只提示不跳转——保留导航界面，
/// 用户通过「我的 → 点击登录」主动重新登录。
void showErr(BuildContext context, Object e, {StackTrace? st}) {
  final msg = e is ApiError ? e.message : e.toString();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4)));
}

/// 页面级加载中 / 出错重试 / 空数据 三态容器。
class PageStateView extends StatelessWidget {
  const PageStateView({
    super.key,
    required this.loading,
    this.error,
    this.empty = false,
    required this.onRetry,
    this.emptyText = '暂无数据',
    required this.child,
  });

  final bool loading;
  final String? error;
  final bool empty;
  final VoidCallback onRetry;
  final String emptyText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()));
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 44, color: SemColors.textMuted),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(error!, textAlign: TextAlign.center,
                  style: TextStyle(color: SemColors.textMuted)),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
    }
    if (empty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(emptyText, style: TextStyle(color: SemColors.textMuted)),
        ),
      );
    }
    return child;
  }
}

/// 未登录提示卡：数据页在游客模式下的占位内容（文案随数据来源模式变化）。
class LoginPrompt extends StatelessWidget {
  const LoginPrompt({super.key, this.title = '未登录'});

  final String title;

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_circle_outlined, size: 56, color: SemColors.textMuted),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              st.direct
                  ? '直连模式：填写学号与统一身份认证密码后\n由本机直接访问学校系统（需在校园网 / 校内 VPN 内）'
                  : '登录服务器账号后查看校园数据\n校园凭据在该服务器网站「我的 → 校园服务」配置一次即可',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: SemColors.textMuted, height: 1.7),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConnectPage()),
              ),
              child: Text(st.direct ? '去填写校园凭据' : '去登录 / 设置服务器'),
            ),
            const SizedBox(height: 10),
            if (kDebugMode)
              OutlinedButton(
                onPressed: () => AppState.I.setDemo(true),
                child: const Text('演示模式（本地假数据）'),
              ),
          ],
        ),
      ),
    );
  }
}

/// 登录门控：未登录时显示 [LoginPrompt]；登录态变化时重建 child（页面重新拉数据）。
class LoginGate extends StatelessWidget {
  const LoginGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final st = AppState.I;
        if (!st.loggedIn) return const LoginPrompt();
        return KeyedSubtree(
          key: ValueKey('gate_${st.demo}_${st.direct}_${st.token != null}_${st.creds.hasLogin}'),
          child: child,
        );
      },
    );
  }
}

const cardRadius = 16.0;

/// 二维码 / 动态码底板（校园码用）：
/// **浅色主题不画白底**——玻璃卡上再叠一块白方块就是用户报过的「背后一个白色正方形」；
/// 深色主题垫圆角白底，否则深色模块在深色卡面上辨认不出、扫不出来。
/// 两种主题都做圆角裁剪：万一服务端返回的是带白底的旧式 PNG，也只看到圆角而非方角。
class QrPlate extends StatelessWidget {
  const QrPlate({super.key, required this.child, this.side = 220});

  final Widget child;
  final double side;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.white : null,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(4),
      child: child,
    );
  }
}

/// 液态玻璃色板（参照 anticlass「夜航玻璃拟态」：玻璃无色、颜色属于场景）。
/// 浅色 = 晨光玻璃（#E3E9F2 底 + 白 55% 玻璃面）；深色 = 规范夜景色（#0B1322 底 + 白 8% 玻璃面）。
/// 强调双色分工：钢蓝（链接/激活/次要高亮）+ 香槟金（主 CTA / 关键数字 / 待办警告语义）。
class GlassPalette {
  const GlassPalette({
    required this.isDark,
    required this.bg,
    required this.card,
    required this.cardElevated,
    required this.navPill,
    required this.menuBg,
    required this.border,
    required this.borderStrong,
    required this.inputFill,
    required this.stripe,
    required this.thumb,
    required this.overlay,
    required this.shadow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.accentStrong,
    required this.gold,
    required this.goldSoft,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
  });

  final bool isDark;
  final Color bg; // 页面底色
  final Color card; // 玻璃卡面
  final Color cardElevated; // 次级玻璃面（嵌套控件底）
  final Color navPill; // 底部悬浮导航条底（比 cardElevated 更实，保证压在内容上可读）
  final Color menuBg; // 弹窗/菜单近实底
  final Color border; // 玻璃描边
  final Color borderStrong; // 输入框/独立控件描边
  final Color inputFill; // 输入框填充
  final Color stripe; // 条带/分组底
  final Color thumb; // 滑块 Tab 的滑动 thumb 面
  final Color overlay; // 弹窗遮罩
  final Color shadow; // 卡片外投影色
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent; // 月光钢蓝
  final Color accentSoft;
  final Color accentStrong;
  final Color gold; // 香槟金（唯一强调色）
  final Color goldSoft;
  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;

  static const light = GlassPalette(
    isDark: false,
    bg: Color(0xFFE3E9F2),
    card: Color(0x8CFFFFFF), // 白 55%
    cardElevated: Color(0x66FFFFFF), // 白 40%
    navPill: Color(0xC7FFFFFF), // 白 78%（底部悬浮导航条：要更实，压在课表上也读得清）
    menuBg: Color(0xF7FFFFFF), // 白 97%
    border: Color(0xB3FFFFFF), // 白 70%
    borderStrong: Color(0xF2FFFFFF), // 白 95%
    inputFill: Color(0xB8FFFFFF), // 白 72%
    stripe: Color(0x0A0B1322), // #0B1322 4%
    thumb: Color(0xD9FFFFFF), // 白 85%
    overlay: Color(0x590B1322), // 35%
    shadow: Color(0x1F030712), // 12%
    textPrimary: Color(0xFF16233A),
    textSecondary: Color(0xBF16233A), // 75%
    textMuted: Color(0x8516233A), // 52%
    accent: Color(0xFF3E639B),
    accentSoft: Color(0x1A3E639B), // 10%
    accentStrong: Color(0x293E639B), // 16%
    gold: Color(0xFF8A6420), // 浅色下加深保证对比
    goldSoft: Color(0x38E4B863), // 22%
    success: Color(0xFF1E7F46),
    successSoft: Color(0x2934C759), // 16%
    danger: Color(0xFFC3372B),
    dangerSoft: Color(0x1FFF3B30), // 12%
  );

  static const dark = GlassPalette(
    isDark: true,
    bg: Color(0xFF0B1322),
    card: Color(0x14FFFFFF), // 白 8%
    cardElevated: Color(0x0FFFFFFF), // 白 6%
    navPill: Color(0x2EFFFFFF), // 白 18%（底部悬浮导航条：深色下也要拉开层次）
    menuBg: Color(0xF5111A2B), // #111A2B 96%
    border: Color(0x26FFFFFF), // 白 15%
    borderStrong: Color(0x52FFFFFF), // 白 32%
    inputFill: Color(0x29FFFFFF), // 白 16%
    stripe: Color(0x0DFFFFFF), // 白 5%
    thumb: Color(0x29FFFFFF), // 白 16%
    overlay: Color(0x99030712), // 60%
    shadow: Color(0x73030712), // 45%
    textPrimary: Color(0xF2FFFFFF), // 白 95%
    textSecondary: Color(0x9EFFFFFF), // 白 62%
    textMuted: Color(0x6BFFFFFF), // 白 42%
    accent: Color(0xFF93B1D4),
    accentSoft: Color(0x1F93B1D4), // 12%
    accentStrong: Color(0x3393B1D4), // 20%
    gold: Color(0xFFE4B863),
    goldSoft: Color(0x24E4B863), // 14%
    success: Color(0xFF3DDC97),
    successSoft: Color(0x293DDC97), // 16%
    danger: Color(0xFFFF6B5E),
    dangerSoft: Color(0x24FF5A4A), // 14%
  );
}

/// 语义色入口（全站 278 处引用）：取值随 [SemColors.p] 当前色板变化，
/// 由 CampusApp 在每次构建时按主题模式写入，MaterialApp 重建带动全站刷新。
class SemColors {
  static GlassPalette p = GlassPalette.light;

  static bool get isDark => p.isDark;
  static Color get accent => p.accent;
  static Color get accentSoft => p.accentSoft;
  static Color get accentStrong => p.accentStrong;
  static Color get success => p.success;
  static Color get successSoft => p.successSoft;
  static Color get danger => p.danger;
  static Color get dangerSoft => p.dangerSoft;
  static Color get warning => p.gold; // 待办/警告 = 香槟金（与 anticlass pending 语义一致）
  static Color get info => p.accent; // 信息 = 钢蓝
  static Color get infoSoft => p.accentSoft;
  static Color get neutralSoft => p.cardElevated;
  static Color get border => p.border;
  static Color get textPrimary => p.textPrimary;
  static Color get textSecondary => p.textSecondary;
  static Color get textMuted => p.textMuted;

  // 玻璃体系新增令牌
  static Color get bg => p.bg;
  static Color get card => p.card;
  static Color get cardElevated => p.cardElevated;
  static Color get navPill => p.navPill;
  static Color get menuBg => p.menuBg;
  static Color get borderStrong => p.borderStrong;
  static Color get inputFill => p.inputFill;
  static Color get stripe => p.stripe;
  static Color get thumb => p.thumb;
  static Color get overlay => p.overlay;
  static Color get shadow => p.shadow;
}

/// 全局液态玻璃场景底：底色 + 三张柔和光源光斑（复刻 anticlass body::before 场景光井）。
/// 玻璃面的「折射感」来自这层光斑透出，玻璃本身不带颜色。
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = SemColors.isDark;
    final wells = dark
        ? const [
            (Alignment(0.7, -0.84), 1.6, Color(0x477C9CC4)), // 右上蓝光斑 28%
            (Alignment(-0.84, 0.84), 1.4, Color(0x5933517A)), // 左下深蓝光斑 35%
            (Alignment(0.1, -0.1), 1.3, Color(0x1AE4B863)), // 中部金光斑 10%
          ]
        : const [
            (Alignment(0.7, -0.84), 1.6, Color(0x807C9CC4)), // 右上蓝光斑 50%
            (Alignment(-0.84, 0.84), 1.4, Color(0x47E4B863)), // 左下金光斑 28%
            (Alignment(-0.1, -0.2), 1.3, Color(0x2933517A)), // 中部蓝光斑 16%
          ];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      ),
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: SemColors.bg)),
          for (final (center, radius, color) in wells)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: center,
                    radius: radius,
                    colors: [color, color.withValues(alpha: 0)],
                    stops: const [0, 0.62],
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// 网站同款状态胶囊徽章：全圆、同色 1px 描边、同色浅底。
class Capsule extends StatelessWidget {
  const Capsule(this.text, {super.key, this.color, this.soft});

  final String text;
  final Color? color;
  final Color? soft;

  @override
  Widget build(BuildContext context) {
    final c = color ?? SemColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: soft ?? c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.55)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

/// 液态玻璃卡片（复刻 anticlass .panel）：半透明玻璃面 + 顶部高光渐变 +
/// 玻璃描边 + 柔和外投影。全站卡片统一入口。
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.onTap, this.radius});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? cardRadius;
    final base = SemColors.card;
    // 顶边白色高光渐变（CSS: linear-gradient 白 10% → 透明 50%），合成进同一渐变
    final top = Color.alphaBlend(Colors.white.withValues(alpha: 0.10), base);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        // 阴影画在 Material/Ink 之外：InkFeature 会被 Material 画布裁剪，
        // 半透明玻璃面下透出方形阴影角
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, base],
            stops: const [0, 0.5],
          ),
          border: Border.all(color: SemColors.border),
          boxShadow: [
            BoxShadow(
                color: SemColors.shadow, offset: const Offset(0, 8), blurRadius: 24),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(r),
            onTap: onTap,
            child: Padding(
              padding: padding ?? const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 液态玻璃滑块 Tab（复刻 anticlass .glass-tabs + .slide-thumb-goo）：
/// 玻璃轨道 + 等宽分栏。thumb 可直接拖拽，松手携带释放速度以弹簧动画
/// 甩到目标段（动量）；点击同样以弹簧滑过去。
class GlassTabs extends StatefulWidget {
  const GlassTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.height = 34,
    this.fontSize = 12.5,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final double height;
  final double fontSize;

  @override
  State<GlassTabs> createState() => _GlassTabsState();
}

class _GlassTabsState extends State<GlassTabs> with SingleTickerProviderStateMixin {
  // unbounded：set value 不被默认 [0,1] 钳制，拖拽边界由自身 clamp 管理
  late final AnimationController _ctrl = AnimationController.unbounded(
      vsync: this, duration: const Duration(milliseconds: 600))
    ..value = widget.index.toDouble();
  int _target = -1;

  // 欠阻尼弹簧：轻微过冲的回弹手感（thumbGoo 手感）
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 260, ratio: 0.72);

  void _springTo(double target, [double velocity = 0]) {
    _target = target.round();
    _ctrl.animateWith(SpringSimulation(_spring, _ctrl.value, target, velocity));
  }

  @override
  void didUpdateWidget(covariant GlassTabs old) {
    super.didUpdateWidget(old);
    // 外部状态变化驱动滑动；自身触发的回调已在动量动画中，不重启
    if (old.index != widget.index && widget.index != _target) {
      _springTo(widget.index.toDouble());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.labels.length;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: SemColors.cardElevated,
        borderRadius: BorderRadius.circular(widget.height / 2 + 3),
        border: Border.all(color: SemColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, cons) {
          final segW = cons.maxWidth / n;
          return SizedBox(
            height: widget.height,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final pos = _ctrl.value.clamp(0.0, (n - 1).toDouble());
                final visual = pos.round().clamp(0, n - 1);
                return Stack(
                  children: [
                    Positioned(
                      left: pos * segW,
                      width: segW,
                      top: 0,
                      height: widget.height,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(widget.height / 2),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color.alphaBlend(
                                  Colors.white.withValues(alpha: 0.25), SemColors.thumb),
                              SemColors.thumb,
                            ],
                          ),
                          border: Border.all(color: SemColors.borderStrong),
                          boxShadow: [
                            BoxShadow(
                                color: SemColors.shadow, offset: const Offset(0, 2), blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < n; i++)
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (i != widget.index) {
                                  _springTo(i.toDouble());
                                  widget.onChanged(i);
                                }
                              },
                              onHorizontalDragStart: (_) => _ctrl.stop(),
                              onHorizontalDragUpdate: (d) =>
                                  _ctrl.value = (_ctrl.value + d.primaryDelta! / segW)
                                      .clamp(0.0, (n - 1).toDouble()),
                              onHorizontalDragEnd: (d) {
                                // 段/秒；速度估计可能爆炸，先饱和
                                final v =
                                    (d.velocity.pixelsPerSecond.dx / segW).clamp(-8.0, 8.0);
                                // 慢速拖拽就近落段；快速甩动（flick）借动量多滑 1 段
                                var target = _ctrl.value.round().clamp(0, n - 1);
                                final next = target + (v > 0 ? 1 : -1);
                                if (v.abs() >= 5.0 && next >= 0 && next <= n - 1) {
                                  target = next;
                                }
                                _springTo(target.toDouble(), v);
                                if (target != widget.index) widget.onChanged(target);
                              },
                              child: Center(
                                child: Text(
                                  widget.labels[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: widget.fontSize,
                                    fontWeight: i == visual ? FontWeight.w600 : FontWeight.w500,
                                    color:
                                        i == visual ? SemColors.textPrimary : SemColors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// anticlass 风格输入框：标签在玻璃面外（上方小字），输入面为独立玻璃块，
/// 避免 M3 浮动标签压在边框缺口上的突兀感。
class GlassField extends StatelessWidget {
  const GlassField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.hintText,
    this.keyboardType,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.textInputAction,
    this.validator,
    this.onSubmitted,
    this.autofillHints,
    this.inputFormatters,
    this.helperText,
    this.helperMaxLines,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? hintText;
  final TextInputType? keyboardType;
  final bool enabled;
  final bool autofocus;
  final int? maxLines;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final String? helperText;
  final int? helperMaxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)
                .copyWith(color: SemColors.textSecondary)),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscureText,
          keyboardType: keyboardType,
          enabled: enabled,
          autofocus: autofocus,
          maxLines: maxLines,
          textInputAction: textInputAction,
          validator: validator,
          autofillHints: autofillHints,
          inputFormatters: inputFormatters,
          onFieldSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            helperText: helperText,
            helperMaxLines: helperMaxLines,
            errorMaxLines: 2,
            isDense: true,
          ),
        ),
      ],
    );
  }
}

/// anticlass 风格下拉选择：标签在面外，同 [GlassField]。
class GlassDropdown<T> extends StatelessWidget {
  const GlassDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<DropdownMenuItem<T>> items;
  final T? value;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)
                .copyWith(color: SemColors.textSecondary)),
        const SizedBox(height: 5),
        DropdownButtonFormField<T>(
          initialValue: value,
          items: items,
          onChanged: onChanged,
          // 展开占满整行：否则长选项（如「DeepSeek · deepseek.com（官方）」）会横向溢出
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
        ),
      ],
    );
  }
}

/// 与 [GlassField] 同款的「点开选择」字段：外观就是输入框，但点它弹出选择器而不是下拉。
/// 长列表（上百个模型）用弹窗 + 筛选才好找，又不想和输入框长得不一样，所以做成一族。
class GlassPicker extends StatelessWidget {
  const GlassPicker({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.hint,
    this.prefixIcon,
    this.helperText,
    this.enabled = true,
  });

  final String label;

  /// 当前值（空串时显示 [hint]）。
  final String value;
  final String? hint;
  final VoidCallback onTap;
  final Widget? prefixIcon;
  final String? helperText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final empty = value.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)
                .copyWith(color: SemColors.textSecondary)),
        const SizedBox(height: 5),
        Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                decoration: BoxDecoration(
                  color: SemColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SemColors.borderStrong),
                ),
                child: Row(
                  children: [
                    if (prefixIcon != null) ...[
                      IconTheme.merge(
                        data: IconThemeData(color: SemColors.textSecondary, size: 20),
                        child: prefixIcon!,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        empty ? (hint ?? '未选择') : value,
                        style: TextStyle(
                          fontSize: 14,
                          color: empty ? SemColors.textMuted : SemColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.expand_more_rounded,
                        size: 20, color: SemColors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Text(helperText!,
              style: TextStyle(fontSize: 11, color: SemColors.textMuted, height: 1.4)),
        ],
      ],
    );
  }
}

/// 提供商品牌 logo：simple-icons 的 CC0 单色 SVG，按当前主题着色（镂空线稿观感）。
/// [asset] 为空（simple-icons 未收录，如 OpenAI / 智谱）时回退成字母徽章——
/// 比随便挑个通用图标更好认。
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    required this.asset,
    required this.initial,
    this.size = 20,
  });

  final String asset;
  final String initial;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (asset.isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: SemColors.neutralSoft,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: SemColors.border),
        ),
        child: Text(
          _badgeText(initial),
          style: TextStyle(
              fontSize: size * 0.46,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: -0.2,
              color: SemColors.textSecondary),
        ),
      );
    }
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(SemColors.textPrimary, BlendMode.srcIn),
    );
  }

  /// 徽章文字：取名称里的拉丁字母/数字前两位（GLM→GL、GPT→GP），否则用首字。
  static String _badgeText(String label) {
    final alnum = RegExp(r'[A-Za-z0-9]').allMatches(label).map((m) => m.group(0)!).join();
    if (alnum.isNotEmpty) {
      final n = alnum.length >= 2 ? 2 : 1;
      return alnum.substring(0, n).toUpperCase();
    }
    final t = label.trim();
    return t.isEmpty ? '?' : t.characters.first.toUpperCase();
  }
}

/// 底栏条目：普通态 / 激活态图标 + 标签。
class GlassNavBarItem {
  const GlassNavBarItem(this.icon, this.activeIcon, this.label);

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// 液态玻璃底栏：thumb 可拖拽、带动量回弹（与 [GlassTabs] 同一物理）。
class GlassNavBar extends StatefulWidget {
  const GlassNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  final List<GlassNavBarItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<GlassNavBar> with SingleTickerProviderStateMixin {
  // unbounded：set value 不被默认 [0,1] 钳制，拖拽边界由自身 clamp 管理
  late final AnimationController _ctrl = AnimationController.unbounded(
      vsync: this, duration: const Duration(milliseconds: 600))
    ..value = widget.index.toDouble();
  int _target = -1;

  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 220, ratio: 0.75);

  void _springTo(double target, [double velocity = 0]) {
    _target = target.round();
    _ctrl.animateWith(SpringSimulation(_spring, _ctrl.value, target, velocity));
  }

  @override
  void didUpdateWidget(covariant GlassNavBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && widget.index != _target) {
      _springTo(widget.index.toDouble());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Container(
          padding: const EdgeInsets.all(4),
          height: 66,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(Colors.white.withValues(alpha: 0.10), SemColors.card),
                SemColors.card,
              ],
              stops: const [0, 0.5],
            ),
            border: Border.all(color: SemColors.border),
            boxShadow: [
              BoxShadow(color: SemColors.shadow, offset: const Offset(0, 8), blurRadius: 24),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, cons) {
              final segW = cons.maxWidth / n;
              return AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final pos = _ctrl.value.clamp(0.0, (n - 1).toDouble());
                  final visual = pos.round().clamp(0, n - 1);
                  return Stack(
                    children: [
                      Positioned(
                        left: pos * segW,
                        width: segW,
                        top: 0,
                        height: 58,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color.alphaBlend(
                                    Colors.white.withValues(alpha: 0.25), SemColors.thumb),
                                SemColors.thumb,
                              ],
                            ),
                            border: Border.all(color: SemColors.borderStrong),
                            boxShadow: [
                              BoxShadow(
                                  color: SemColors.shadow,
                                  offset: const Offset(0, 2),
                                  blurRadius: 8),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (var i = 0; i < n; i++)
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  if (i != widget.index) {
                                    _springTo(i.toDouble());
                                    HapticFeedback.selectionClick();
                                    widget.onChanged(i);
                                  }
                                },
                                onHorizontalDragStart: (_) => _ctrl.stop(),
                                onHorizontalDragUpdate: (d) =>
                                    _ctrl.value = (_ctrl.value + d.primaryDelta! / segW)
                                        .clamp(0.0, (n - 1).toDouble()),
                                onHorizontalDragEnd: (d) {
                                  // 段/秒；速度估计可能爆炸，先饱和
                                  final v =
                                      (d.velocity.pixelsPerSecond.dx / segW).clamp(-8.0, 8.0);
                                  // 慢速拖拽就近落段；快速甩动（flick）借动量多滑 1 段
                                  var target = _ctrl.value.round().clamp(0, n - 1);
                                  final next = target + (v > 0 ? 1 : -1);
                                  if (v.abs() >= 5.0 && next >= 0 && next <= n - 1) {
                                    target = next;
                                  }
                                  _springTo(target.toDouble(), v);
                                  if (target != widget.index) {
                                    HapticFeedback.selectionClick();
                                    widget.onChanged(target);
                                  }
                                },
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(widget.items[i].icon,
                                        size: 22,
                                        color: i == visual
                                            ? SemColors.accent
                                            : SemColors.textMuted),
                                    const SizedBox(height: 2),
                                    Text(widget.items[i].label,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight:
                                              i == visual ? FontWeight.w600 : FontWeight.w500,
                                          color: i == visual
                                              ? SemColors.accent
                                              : SemColors.textMuted,
                                        )),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 30px/600 大数字统计（网站 .cs-stat）。
class BigStat extends StatelessWidget {
  const BigStat({super.key, required this.label, required this.value, this.suffix, this.color});

  final String label;
  final String value;
  final String? suffix;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w600, height: 1.1,
                    color: color ?? SemColors.textPrimary)),
            if (suffix != null) ...[
              const SizedBox(width: 4),
              Text(suffix!,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: SemColors.textSecondary)),
            ],
          ],
        ),
      ],
    );
  }
}
