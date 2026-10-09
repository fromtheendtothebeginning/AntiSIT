import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 墨白极简：不透明卡面 + 细描边 + 墨色强调，去掉玻璃与光斑，字色对比更高。
/// 色板由少量基色派生（GlassPalette.flat），不必手写 26 个令牌。
class InkTheme extends ThemePlugin {
  const InkTheme();

  static const themeId = 'theme.ink';

  @override
  String get id => themeId;
  @override
  String get name => '墨白极简';
  @override
  String get description => '不透明卡面 + 细灰描边，去掉玻璃与光斑，字色对比最高';

  @override
  GlassPalette palette(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  static final _light = GlassPalette.flat(
    isDark: false,
    bg: const Color(0xFFF4F4F2),
    surface: Colors.white,
    accent: const Color(0xFF2C3340),
    gold: const Color(0xFF8A6420),
    success: const Color(0xFF1E7F46),
    danger: const Color(0xFFC3372B),
    text: const Color(0xFF1B1F27),
  );

  static final _dark = GlassPalette.flat(
    isDark: true,
    bg: const Color(0xFF111318),
    surface: const Color(0xFF1B1F26),
    accent: const Color(0xFFC8D2E0),
    gold: const Color(0xFFE4B863),
    success: const Color(0xFF3DDC97),
    danger: const Color(0xFFFF6B5E),
    text: const Color(0xFFF2F3F5),
  );
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关 EXCLUDE_THEME_INK 为真时，这一条连同包内代码一起被摇掉。
const PluginBundle pluginBundle = PluginBundle(themes: [InkTheme()]);
