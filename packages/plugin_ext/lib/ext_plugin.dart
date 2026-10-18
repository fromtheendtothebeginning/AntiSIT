import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'extensions_page.dart';

/// 拓展：网页形态的小功能，用户自己填网址 / 导入 JSON 添加，点开就是对应网页。
///
/// * **默认关闭**（[defaultEnabled]）：装进来但先不占底栏，用户在「插件管理」里
///   自己打开；打开与否会被记住。
/// * **依赖 WebView 内核**（[dependencies]）：拓展跑在内核上，所以启用本插件会
///   连带启用 `webview`，停用内核会把本插件一起停掉（关系图上是一条实线）。
/// * 初始**没有任何内置拓展**，清单从空开始，全靠用户自己加（见 [ExtensionStore]）
///   或从**插件市场**装（见 `market/`）。
class ExtPlugin extends FeaturePlugin {
  const ExtPlugin();

  static const pluginId = 'ext';

  @override
  String get id => pluginId;
  @override
  String get name => '拓展';
  @override
  String get description => '网页形态的小功能：从市场装、自己填网址或导入压缩包，点开就是对应网页';
  @override
  List<String> get dependencies => const [PluginIds.webview];
  @override
  bool get defaultEnabled => false;

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
/// 编译期常量开关为真时（--dart-define=EXCLUDE_EXT=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [ExtPlugin()]);
