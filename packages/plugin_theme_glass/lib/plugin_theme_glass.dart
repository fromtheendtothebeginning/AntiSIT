import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 液态玻璃（默认主题）：手调的玻璃色板——浅色 = 晨光玻璃，深色 = 夜航玻璃。
/// 玻璃无色、颜色属于场景，所以它自带一组场景光斑。
class GlassTheme extends ThemePlugin {
  const GlassTheme();

  static const themeId = PluginIds.themeGlass;

  @override
  String get id => themeId;
  @override
  String get name => '液态玻璃';
  @override
  String get description => '默认主题：半透明玻璃面 + 场景光斑，玻璃无色、颜色属于场景';

  @override
  GlassPalette palette(Brightness brightness) =>
      brightness == Brightness.dark ? GlassPalette.dark : GlassPalette.light;

  @override
  List<GlassWell> wells(Brightness brightness) =>
      brightness == Brightness.dark ? kGlassWellsDark : kGlassWellsLight;
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关 EXCLUDE_THEME_GLASS 为真时，这一条连同包内代码一起被摇掉。
const PluginBundle pluginBundle = PluginBundle(themes: [GlassTheme()]);
