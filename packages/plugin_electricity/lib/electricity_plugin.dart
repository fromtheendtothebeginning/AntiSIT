import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';
import 'electricity_page.dart';

/// 宿舍电费：余额查询、充值、历史余额折线图。
class ElectricityPlugin extends FeaturePlugin {
  const ElectricityPlugin();

  static const pluginId = 'electricity';

  @override
  String get id => pluginId;
  @override
  String get name => '宿舍电费';
  @override
  String get description => '余额查询、充值、历史余额折线图';
  @override
  List<String> get dependencies => const [PluginIds.network];

  @override
  List<PluginTool> tools(PluginRegistry registry) => [
        PluginTool(
          icon: Icons.bolt_rounded,
          color: Colors.amber.shade700,
          title: '宿舍电费',
          subtitle: _subtitle,
          open: () => const ElectricityPage(),
        ),
      ];

  static String _subtitle() {
    final e = ToolCache.electricity;
    if (e == null) return '余额查询与充值';
    return '余额 ¥${e['balance']}';
  }

  @override
  Future<void> prefetch() async {
    final r = await ApiClient.I.electricityQuery();
    ToolCache.electricity = r['data'] as Map<String, dynamic>?;
  }
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_XXX=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [ElectricityPlugin()]);
