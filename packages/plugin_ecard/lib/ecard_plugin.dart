import 'package:flutter/material.dart';

import 'ecard_page.dart';
import 'package:campus_core/campus_core.dart';

/// 校园码：动态付款码（55 秒自动刷新）+ 校园卡余额，仅在本页可见时刷新。
class EcardPlugin extends FeaturePlugin {
  const EcardPlugin();

  static const pluginId = 'ecard';

  @override
  String get id => pluginId;
  @override
  String get name => '校园码';
  @override
  String get description => '动态付款码（55 秒自动刷新）与校园卡余额，亮码期间屏幕常亮';
  @override
  List<String> get dependencies => const [PluginIds.network];

  @override
  List<PluginNavItem> navItems(registry, tab) => [
        PluginNavItem(
          icon: Icons.qr_code_2_outlined,
          activeIcon: Icons.qr_code_2,
          label: '校园码',
          order: 20,
          // myTab 取底栏实时下标：前面有插件被停用时会前移，不能写死。
          build: (index) => EcardPage(activeTab: tab, myTab: index),
        ),
      ];
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_XXX=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [EcardPlugin()]);
