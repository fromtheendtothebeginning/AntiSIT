import 'package:flutter/material.dart';

import 'exams_page.dart';
import 'package:campus_core/campus_core.dart';

/// 考试安排：期中 / 期末的时间、地点、座位。
class ExamsPlugin extends FeaturePlugin {
  const ExamsPlugin();

  static const pluginId = 'exams';

  @override
  String get id => pluginId;
  @override
  String get name => '考试安排';
  @override
  String get description => '期中 / 期末安排';
  @override
  List<String> get dependencies => const [PluginIds.network];

  @override
  List<PluginTool> tools(PluginRegistry registry) => [
        PluginTool(
          icon: Icons.event_note_rounded,
          color: Colors.orange,
          title: '考试安排',
          subtitle: () => '期中 / 期末安排',
          open: () => const ExamsPage(),
        ),
      ];
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_XXX=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [ExamsPlugin()]);
