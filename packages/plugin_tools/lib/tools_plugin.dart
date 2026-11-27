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
  String get description => '已启用工具的宫格入口；一个工具都没有时自动从底栏隐藏';

  /// 扫一扫是软依赖：工具页右上角的扫码入口有就用、没有就不显示。
  /// （条码分流由扫一扫插件自己做：二课签到码 / 活动码 / 拓展安装码…）
  @override
  List<String> get optionalDependencies => const [PluginIds.scan];

  @override
  List<PluginNavItem> navItems(registry, tab) {
    if (registry.toolCards.isEmpty) return const [];
    return [
      PluginNavItem(
        icon: Icons.widgets_outlined,
        activeIcon: Icons.widgets_outlined,
        label: '工具',
        order: 30,
        build: (_) => const ToolsPage(),
      ),
    ];
  }
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；--dart-define=EXCLUDE_TOOLS=true 时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(features: [ToolsPlugin()]);