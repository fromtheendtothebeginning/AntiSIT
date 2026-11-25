import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 当前配色：把原生色板的全部令牌交给拓展，AntiUI 直接映射成 CSS 变量。
Map<String, Object?> extensionThemeJson() {
  final p = SemColors.p;
  final brightness = p.isDark ? Brightness.dark : Brightness.light;
  final theme = PluginRegistry.I.theme;
  return {
    'isDark': p.isDark,
    'themeId': theme.id,
    'themeName': theme.name,
    'bg': cssHexColor(p.bg),
    'card': cssHexColor(p.card),
    'cardElevated': cssHexColor(p.cardElevated),
    'navPill': cssHexColor(p.navPill),
    'menuBg': cssHexColor(p.menuBg),
    'border': cssHexColor(p.border),
    'borderStrong': cssHexColor(p.borderStrong),
    'inputFill': cssHexColor(p.inputFill),
    'stripe': cssHexColor(p.stripe),
    'thumb': cssHexColor(p.thumb),
    'overlay': cssHexColor(p.overlay),
    'shadow': cssHexColor(p.shadow),
    'textPrimary': cssHexColor(p.textPrimary),
    'textSecondary': cssHexColor(p.textSecondary),
    'textMuted': cssHexColor(p.textMuted),
    'accent': cssHexColor(p.accent),
    'accentSoft': cssHexColor(p.accentSoft),
    'accentStrong': cssHexColor(p.accentStrong),
    'gold': cssHexColor(p.gold),
    'goldSoft': cssHexColor(p.goldSoft),
    'warning': cssHexColor(p.gold),
    'warningSoft': cssHexColor(p.goldSoft),
    'success': cssHexColor(p.success),
    'successSoft': cssHexColor(p.successSoft),
    'danger': cssHexColor(p.danger),
    'dangerSoft': cssHexColor(p.dangerSoft),
    // 主按钮文字色：深色主题下强调色偏亮，用页面底色才够对比（与 FilledButton 一致）
    'onAccent': cssHexColor(p.isDark ? p.bg : Colors.white),
    // 形状令牌与 buildAppTheme 保持一致，拓展不用猜圆角
    'radiusCard': 16,
    'radiusControl': 12,
    'radiusButton': 16,
    'radiusDialog': 24,
    'radiusSheet': 24,
    'radiusPill': 999,
    // 场景光斑：玻璃主题才有，非玻璃主题是空数组
    'wells': [
      for (final w in theme.wells(brightness))
        {
          'x': w.center.x,
          'y': w.center.y,
          'radius': w.radius,
          'color': cssHexColor(w.color),
        },
    ],
  };
}

/// CSS 颜色：带透明度输出 `rgba()`（CSS 的 8 位 hex 是 RRGGBBAA，与 Android 的
/// ARGB 相反，丢掉 alpha 会让玻璃主题的半透明卡白成一片）。
String cssHexColor(Color c) {
  final v = c.toARGB32();
  final a = (v >> 24) & 0xFF;
  final r = (v >> 16) & 0xFF;
  final g = (v >> 8) & 0xFF;
  final b = v & 0xFF;
  String hx(int x) => x.toRadixString(16).padLeft(2, '0');
  if (a == 0xFF) return '#${hx(r)}${hx(g)}${hx(b)}';
  return 'rgba($r, $g, $b, ${(a / 255).toStringAsFixed(3)})';
}
