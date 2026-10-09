import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 青竹：浅青底 + 深青强调色，冷暖介于玻璃与墨白之间。
/// 色板由少量基色派生（GlassPalette.flat），不必手写 26 个令牌。
class BambooTheme extends ThemePlugin {
  const BambooTheme();

  static const themeId = 'theme.bamboo';

  @override
  String get id => themeId;
  @override
  String get name => '青竹';
  @override
  String get description => '浅青底 + 深青强调色，柔和不刺眼';

  @override
  GlassPalette palette(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  static final _light = GlassPalette.flat(
    isDark: false,
    bg: const Color(0xFFEDF1EC),
    surface: Colors.white,
    accent: const Color(0xFF1F6F5C),
    gold: const Color(0xFF8A6420),
    success: const Color(0xFF1E7F46),
    danger: const Color(0xFFC3372B),
    text: const Color(0xFF1C2A26),
  );

  static final _dark = GlassPalette.flat(
    isDark: true,
    bg: const Color(0xFF0E1A17),
    surface: const Color(0xFF16241F),
    accent: const Color(0xFF7FC6AE),
    gold: const Color(0xFFE4B863),
    success: const Color(0xFF46D39A),
    danger: const Color(0xFFFF6B5E),
    text: const Color(0xFFEAF1EE),
  );
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关 EXCLUDE_THEME_BAMBOO 为真时，这一条连同包内代码一起被摇掉。
const PluginBundle pluginBundle = PluginBundle(themes: [BambooTheme()]);
