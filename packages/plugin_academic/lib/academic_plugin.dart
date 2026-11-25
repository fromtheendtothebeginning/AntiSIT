import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'academic_page.dart';

/// 学业情况：学生学业情况查询（正方 N105515）——平均学分绩点、计划内外课程通过数、
/// 培养方案各类别学分要求与课程明细；直连 / 服务器（`/api/campus-open/academic`）两种模式。
class AcademicPlugin extends FeaturePlugin {
  const AcademicPlugin();

  static const pluginId = 'academic';

  @override
  String get id => pluginId;
  @override
  String get name => '学业情况';
  @override
  String get description => '学分要求、已修情况与类别课程明细';
  @override
  List<String> get dependencies => const [PluginIds.network, PluginIds.tools];

  @override
  List<PluginTool> tools(PluginRegistry registry) => [
        PluginTool(
          icon: Icons.school_outlined,
          color: Colors.teal,
          title: '学业情况',
          subtitle: () => '学分要求、已修情况与类别课程明细',
          open: () => const AcademicPage(),
        ),
      ];
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；--dart-define=EXCLUDE_ACADEMIC=true 时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(features: [AcademicPlugin()]);
