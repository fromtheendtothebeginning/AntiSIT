import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'extensions_page.dart';

/// 拓展：网页形态的小功能，用户自己填网址 / 导入 JSON 添加，点开就是对应网页。
///
/// 默认开启、依赖 WebView 内核（启用本插件会连带启用 `webview`，停内核则一起停）；
/// 初始没有任何内置拓展，清单从空开始。
class ExtPlugin extends FeaturePlugin {
  const ExtPlugin();

  static const pluginId = 'ext';

  @override
  String get id => pluginId;
  @override
  String get name => '拓展';
  @override
  String get description => '把网页变成小功能：市场安装、填网址或导入压缩包，点开即用';
  @override
  List<String> get dependencies => const [PluginIds.webview];

  /// AI 是软依赖：`ai.chat` 只在 AI 插件可用时工作，没装 / 停用 / 没配置就报错回网页。
  /// 扫一扫同理：插件在就显示右上角入口。
  @override
  List<String> get optionalDependencies => const [PluginIds.ai, PluginIds.scan];

  @override
  bool get defaultEnabled => true;

  @override
  List<PluginNavItem> navItems(PluginRegistry registry, ValueListenable<int> tab) => [
        PluginNavItem(
          icon: Icons.extension_outlined,
          activeIcon: Icons.extension,
          label: '拓展',
          order: 40,
          build: (_) => const ExtensionsPage(),
        ),
      ];
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期开关为真时（--dart-define=EXCLUDE_EXT=true）这条连同包内代码一起不可达，被摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [ExtPlugin()]);
