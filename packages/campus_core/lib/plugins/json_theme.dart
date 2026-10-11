import 'dart:convert';

import 'package:flutter/material.dart' show Brightness, Color;

import '../widgets/common.dart';
import 'plugin.dart';

/// 由 JSON 数据驱动的自定义主题——「导入主题」功能的载体。
///
/// 把前端的主题**抽象成数据**：一份 JSON 描述浅色 / 深色两套「底色 + 面底 +
/// 强调色 + 文字色」，[GlassPalette.flat] 负责派生整套令牌（透明度 / 描边档位
/// 与内置色板一致），界面与普通主题插件无异。
///
/// JSON 形如（颜色支持 `#RRGGBB` / `#AARRGGBB`）：
/// ```json
/// {
///   "name": "我的主题",
///   "light": { "bg": "#E3E9F2", "surface": "#FFFFFF", "accent": "#3E639B",
///              "gold": "#8A6420", "text": "#16233A" },
///   "dark":  { "bg": "#0B1322", "surface": "#111A2B", "accent": "#93B1D4",
///              "gold": "#E4B863", "text": "#FFFFFF" }
/// }
/// ```
/// `success` / `danger` 可省略（给默认绿 / 红）。导入后持久化在注册表里，
/// 与内置主题一样出现在选择器中。
class JsonThemePlugin extends ThemePlugin {
  const JsonThemePlugin({
    required this.id,
    required this.name,
    required this.light,
    required this.dark,
  });

  /// 从 JSON 字符串解析；格式不对抛 [FormatException]，message 是给人看的原因。
  factory JsonThemePlugin.parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw FormatException('不是合法的 JSON：${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('根节点应当是一个 JSON 对象');
    }
    final m = decoded;
    final name = '${m['name'] ?? ''}'.trim();
    if (name.isEmpty) throw const FormatException('缺少 name（主题名）');
    final light = _paletteOf(m['light'], 'light');
    final dark = _paletteOf(m['dark'], 'dark');
    final id = '${m['id'] ?? ''}'.trim().isNotEmpty
        ? '${m['id']}'
        : 'custom.${name.hashCode.toRadixString(36)}';
    return JsonThemePlugin(id: id, name: name, light: light, dark: dark);
  }

  final String id;

  @override
  final String name;

  /// 每档的五个基础色：bg / surface / accent / gold / text（success、danger 可选）。
  final Map<String, Color> light;
  final Map<String, Color> dark;

  /// 备份用：把主题还原成可再导入的 JSON（id 一并带上，重复导入按 id 覆盖）。
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'light': {for (final e in light.entries) e.key: _hex(e.value)},
        'dark': {for (final e in dark.entries) e.key: _hex(e.value)},
      };

  static Map<String, Color> _paletteOf(Object? node, String which) {
    if (node is! Map<String, dynamic>) {
      throw FormatException('缺少 $which（该档色板，含 bg / surface / accent / gold / text）');
    }
    Color require(String key) {
      final raw = '${node[key] ?? ''}'.trim();
      final c = _colorOf(raw);
      if (c == null) throw FormatException('$which.$key 不是合法的颜色值：\"$raw\"');
      return c;
    }

    return {
      'bg': require('bg'),
      'surface': require('surface'),
      'accent': require('accent'),
      'gold': require('gold'),
      'text': require('text'),
      'success': node['success'] == null ? _defaultSuccess(which) : require('success'),
      'danger': node['danger'] == null ? _defaultDanger(which) : require('danger'),
    };
  }

  static Color _defaultSuccess(String which) => which == 'dark'
      ? const Color(0xFF3DDC97)
      : const Color(0xFF1E7F46);
  static Color _defaultDanger(String which) =>
      which == 'dark' ? const Color(0xFFFF6B5E) : const Color(0xFFC3372B);

  /// `#RRGGBB` / `#AARRGGBB`（# 可省）。
  static Color? _colorOf(String raw) {
    var s = raw.replaceAll('#', '').trim();
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    final v = int.tryParse(s, radix: 16);
    if (v == null) return null;
    return Color(v);
  }

  static String _hex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  Map<String, Color> _of(Brightness b) => b == Brightness.dark ? dark : light;

  @override
  String get description => '导入的自定义主题';

  @override
  GlassPalette palette(Brightness brightness) {
    final p = _of(brightness);
    return GlassPalette.flat(
      isDark: brightness == Brightness.dark,
      bg: p['bg']!,
      surface: p['surface']!,
      accent: p['accent']!,
      gold: p['gold']!,
      success: p['success']!,
      danger: p['danger']!,
      text: p['text']!,
    );
  }
}
