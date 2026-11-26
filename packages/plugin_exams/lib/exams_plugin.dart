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
  String get description => '期中 / 期末的考试时间、地点与座位';
  @override
  List<String> get dependencies => const [PluginIds.network, PluginIds.tools];

  @override
  List<PluginTool> tools(PluginRegistry registry) => [
        PluginTool(
          icon: Icons.event_note_outlined,
          color: Colors.orange,
          title: '考试安排',
          subtitle: () => '期中 / 期末的考试时间、地点与座位',
          open: () => const ExamsPage(),
        ),
      ];
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；--dart-define=EXCLUDE_EXAMS=true 时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(features: [ExamsPlugin()]);
