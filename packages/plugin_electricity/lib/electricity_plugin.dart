import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';
import 'electricity_page.dart';

/// 宿舍电费：查余额、充值、历史余额曲线。
class ElectricityPlugin extends FeaturePlugin {
  const ElectricityPlugin();

  static const pluginId = 'electricity';

  @override
  String get id => pluginId;
  @override
  String get name => '宿舍电费';
  @override
  String get description => '查余额、充值、看历史余额曲线';
  @override
  List<String> get dependencies => const [PluginIds.network];

  /// 软依赖（不联动启停）：风险提醒开着时本插件的充值入口被拦下（见 [RiskNoticeCapability]），
  /// 关掉它立即恢复；没装风险提醒则等同没有这道闸。
  @override
  List<String> get optionalDependencies => const [PluginIds.risk];

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
