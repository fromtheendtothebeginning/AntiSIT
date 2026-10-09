import 'package:flutter/material.dart';

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
  String get description => '报名状态一览';
  @override
  List<String> get dependencies => const [PluginIds.network];

  @override
  List<PluginTool> tools(PluginRegistry registry) => [
        PluginTool(
          icon: Icons.local_activity_rounded,
          color: Colors.purple,
          title: '二课活动',
          subtitle: () => '报名状态一览',
          open: () => const ActivitiesPage(),
        ),
      ];
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_XXX=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [ActivitiesPlugin()]);
