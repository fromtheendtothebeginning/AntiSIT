import 'package:flutter/material.dart';

import 'tools_page.dart';
import 'package:campus_core/campus_core.dart';

/// 工具中心：汇聚各工具插件的宫格页（自己不提供任何工具）。
/// 一个工具都没启用时连底栏这一格也不占——空页面没有存在意义。
class ToolsPlugin extends FeaturePlugin {
  const ToolsPlugin();

  static const pluginId = 'tools';

  @override
  String get id => pluginId;
  @override
  String get name => '工具中心';
  @override
  String get description => '汇聚成绩 / 考试 / 二课 / 电费等工具的宫格页；没有任何工具启用时自动从底栏隐藏';

  @override
  List<PluginNavItem> navItems(registry, tab) {
    if (registry.toolCards.isEmpty) return const [];
    return [
      PluginNavItem(
        icon: Icons.widgets_outlined,
        activeIcon: Icons.widgets,
        label: '工具',
        order: 30,
        build: (_) => const ToolsPage(),
      ),
    ];
  }
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_XXX=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [ToolsPlugin()]);
