import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'academic_page.dart';

/// 学业情况：学生学业情况查询（正方 N105515）——平均学分绩点、计划内外课程
/// 通过数、培养方案各类别学分要求，以及每个类别下的课程明细。
///
/// 直连 / 服务器两种模式都支持（服务器模式走开放接口 `/api/campus-open/academic`）。
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
  List<PluginTool> tools(PluginRegistry registry) => AppState.I.demo
      ? const [] // 演示模式是本地假数据，学业情况没有对应假数据，不显示入口
      : [
          PluginTool(
            icon: Icons.school_rounded,
            color: Colors.teal,
            title: '学业情况',
            subtitle: () => '学分要求、已修情况与类别课程明细',
            open: () => const AcademicPage(),
          ),
        ];
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_ACADEMIC=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [AcademicPlugin()]);
