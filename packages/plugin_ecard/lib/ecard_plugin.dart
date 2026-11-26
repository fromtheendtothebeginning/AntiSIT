import 'package:flutter/material.dart';

import 'ecard_page.dart';
import 'package:campus_core/campus_core.dart';

/// 校园码：动态付款码（默认 10 秒刷新，间隔可在「我的 → 配置」调整）+ 余额。
class EcardPlugin extends FeaturePlugin {
  const EcardPlugin();

  static const pluginId = 'ecard';

  @override
  String get id => pluginId;
  @override
  String get name => '校园码';
  @override
  String get description => '校园卡动态付款码（默认 10 秒换一张，间隔可调）与余额，亮码时屏幕常亮';
  @override
  List<String> get dependencies => const [PluginIds.network];

  /// 软依赖（不联动启停）：风险提醒开着时付款码被拦下，关掉立即恢复；
  /// 桌面卡片同理，装了就把余额同步过去。
  @override
  List<String> get optionalDependencies =>
      const [PluginIds.risk, PluginIds.homeWidget];

  @override
  List<PluginNavItem> navItems(registry, tab) => [
        PluginNavItem(
          icon: Icons.qr_code_2_outlined,
          activeIcon: Icons.qr_code_2_outlined,
          label: '校园码',
          order: 20,
          // myTab 取底栏实时下标：前面有插件被停用时会前移，不能写死。
          build: (index) => EcardPage(activeTab: tab, myTab: index),
        ),
      ];
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；--dart-define=EXCLUDE_ECARD=true 时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(features: [EcardPlugin()]);
