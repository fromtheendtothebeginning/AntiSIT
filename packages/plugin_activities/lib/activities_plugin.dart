import 'package:flutter/material.dart';

import 'activities_capability_impl.dart';
import 'activities_page.dart';
import 'package:campus_core/campus_core.dart';

/// 二课活动：报名状态看板、关键词搜索、排序。
class ActivitiesPlugin extends FeaturePlugin {
  const ActivitiesPlugin();

  static const pluginId = 'activities';

  @override
  String get id => pluginId;
  @override
  String get name => '二课活动';
  @override
  String get description => '第二课堂活动：报名状态、时间名额与在线报名';
  @override
  List<String> get dependencies => const [PluginIds.network, PluginIds.tools];

  /// 扫一扫是软依赖：活动页右上角的扫码入口有就用、没有就不显示。
  @override
  List<String> get optionalDependencies => const [PluginIds.scan];

  @override
  List<PluginTool> tools(PluginRegistry registry) => [
        PluginTool(
          icon: Icons.local_activity_outlined,
          color: Colors.purple,
          title: '二课活动',
          subtitle: () => '第二课堂活动：报名状态、时间名额与在线报名',
          open: () => const ActivitiesPage(),
        ),
      ];
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_XXX=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(
  features: [ActivitiesPlugin()],
  // 活动详情页也对外：扫码插件扫到活动码时按能力取用，不 import 本包
  capabilities: {PluginIds.activities: ActivitiesCapabilityImpl()},
);
