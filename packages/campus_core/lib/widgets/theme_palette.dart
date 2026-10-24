import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  static const light = GlassPalette(    isDark: false,
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
    navPill: Color(0x47FFFFFF), // 白 28%（底部悬浮导航条：深色下压在课表格子上，「第 x 周」要看得清）
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

  /// 两套色板按 [t] 插值（0 = [a] 原样、1 = [b] 原样）：拖动「外观」滑块时整站配色
  /// 就靠它渐变——拖到 0.5 时页面底色/卡面/文字都是浅深各一半，松手落到所选那档。
  /// 每个令牌一视同仁地 `Color.lerp`（含 alpha），`isDark` 取更近的那一档
  /// （状态栏图标、场景光斑按它选）。
  static GlassPalette lerp(GlassPalette a, GlassPalette b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    Color mix(Color x, Color y) => Color.lerp(x, y, t)!;
    return GlassPalette(
      isDark: t >= 0.5 ? b.isDark : a.isDark,
      bg: mix(a.bg, b.bg),
      card: mix(a.card, b.card),
      cardElevated: mix(a.cardElevated, b.cardElevated),
      navPill: mix(a.navPill, b.navPill),
      menuBg: mix(a.menuBg, b.menuBg),
      border: mix(a.border, b.border),
      borderStrong: mix(a.borderStrong, b.borderStrong),
      inputFill: mix(a.inputFill, b.inputFill),
      stripe: mix(a.stripe, b.stripe),
      thumb: mix(a.thumb, b.thumb),
      overlay: mix(a.overlay, b.overlay),
      shadow: mix(a.shadow, b.shadow),
      textPrimary: mix(a.textPrimary, b.textPrimary),
      textSecondary: mix(a.textSecondary, b.textSecondary),
      textMuted: mix(a.textMuted, b.textMuted),
      accent: mix(a.accent, b.accent),
      accentSoft: mix(a.accentSoft, b.accentSoft),
      accentStrong: mix(a.accentStrong, b.accentStrong),
      gold: mix(a.gold, b.gold),
      goldSoft: mix(a.goldSoft, b.goldSoft),
      success: mix(a.success, b.success),
      successSoft: mix(a.successSoft, b.successSoft),
      danger: mix(a.danger, b.danger),
      dangerSoft: mix(a.dangerSoft, b.dangerSoft),
    );
  }

  /// 由「底色 + 面底 + 强调色」派生整套令牌（透明/描边档位与原玻璃色板一致）。
  /// 非玻璃主题用它构造即可，不必手写 26 个令牌；液态玻璃仍保留上面手调的常量。
  factory GlassPalette.flat({
    required bool isDark,
    required Color bg,
    required Color surface,
    required Color accent,
    required Color gold,
    required Color success,
    required Color danger,
    required Color text,
  }) {
    Color soft(Color c, double a) => c.withValues(alpha: a);
    const ink = Color(0xFF0B1322); // 遮罩/投影的中性基色（浅色下当墨色用）
    return GlassPalette(
      isDark: isDark,
      bg: bg,
      card: surface,
      cardElevated: isDark ? soft(Colors.white, 0.06) : soft(ink, 0.03),
      navPill: surface,
      menuBg: surface,
      border: isDark ? soft(Colors.white, 0.12) : soft(ink, 0.12),
      borderStrong: isDark ? soft(Colors.white, 0.26) : soft(ink, 0.26),
      inputFill: isDark ? soft(Colors.white, 0.08) : soft(ink, 0.04),
      stripe: isDark ? soft(Colors.white, 0.05) : soft(ink, 0.04),
      thumb: isDark ? soft(Colors.white, 0.18) : Colors.white,
      overlay: soft(ink, isDark ? 0.60 : 0.35),
      shadow: soft(ink, isDark ? 0.45 : 0.12),
      textPrimary: text,
      textSecondary: soft(text, 0.75),
      textMuted: soft(text, 0.52),
      accent: accent,
      accentSoft: soft(accent, 0.10),
      accentStrong: soft(accent, 0.16),
      gold: gold,
      goldSoft: soft(gold, 0.18),
      success: success,
      successSoft: soft(success, 0.14),
      danger: danger,
      dangerSoft: soft(danger, 0.12),
    );
  }
}

/// 场景光斑：圆心、半径、颜色。玻璃主题的「折射感」来自这些光斑透出玻璃面。
class GlassWell {
  const GlassWell(this.center, this.radius, this.color);

  final Alignment center;
  final double radius;
  final Color color;
}

/// 液态玻璃的默认光井（复刻 anticlass body::before 场景光井）。
const kGlassWellsLight = <GlassWell>[
  GlassWell(Alignment(0.7, -0.84), 1.6, Color(0x807C9CC4)), // 右上蓝光斑 50%
  GlassWell(Alignment(-0.84, 0.84), 1.4, Color(0x47E4B863)), // 左下金光斑 28%
  GlassWell(Alignment(-0.1, -0.2), 1.3, Color(0x2933517A)), // 中部蓝光斑 16%
];

const kGlassWellsDark = <GlassWell>[
  GlassWell(Alignment(0.7, -0.84), 1.6, Color(0x477C9CC4)), // 右上蓝光斑 28%
  GlassWell(Alignment(-0.84, 0.84), 1.4, Color(0x5933517A)), // 左下深蓝光斑 35%
  GlassWell(Alignment(0.1, -0.1), 1.3, Color(0x1AE4B863)), // 中部金光斑 10%
];

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

/// 全局场景底：底色 + 若干柔和光源光斑。玻璃主题传入自己的光斑
/// （[GlassWell] 由主题插件给），不传就用液态玻璃的默认光井。
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child, this.wells});

  final Widget child;
  final List<GlassWell>? wells;

  @override
  Widget build(BuildContext context) {
    final dark = SemColors.isDark;
    final spots = wells ?? (dark ? kGlassWellsDark : kGlassWellsLight);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      ),
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: SemColors.bg)),
          for (final w in spots)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: w.center,
                    radius: w.radius,
                    colors: [w.color, w.color.withValues(alpha: 0)],
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

