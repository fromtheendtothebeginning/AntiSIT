import 'package:flutter/material.dart';

import 'grades_page.dart';
import 'package:campus_core/campus_core.dart';

/// 成绩单：全部学期 / 按学期查询，平均绩点与学分绩点一览。
class GradesPlugin extends FeaturePlugin {
  const GradesPlugin();

  static const pluginId = 'grades';

  @override
  String get id => pluginId;
  @override
  String get name => '成绩单';
  @override
  String get description => '各学期成绩、学分与 GPA';
  @override
  List<String> get dependencies => const [PluginIds.network, PluginIds.tools];

  @override
  List<PluginTool> tools(PluginRegistry registry) => [
    PluginTool(
      icon: Icons.fact_check_outlined,
      color: Colors.blue,
      title: '成绩单',
      subtitle: () => '各学期成绩、学分与 GPA',
      open: () => const GradesPage(),
    ),
  ];
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；--dart-define=EXCLUDE_GRADES=true 时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(features: [GradesPlugin()]);
