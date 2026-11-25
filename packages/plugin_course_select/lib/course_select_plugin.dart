import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'course_select_page.dart';

/// 抢课：正方教务 9.0「学生选课」——选课轮次、课程余量、教学班展开与自动抢课。
/// 选课是写操作，只支持直连模式（设备在校园网 / 校内 VPN 内），服务器模式暂无选课端点。
class CourseSelectPlugin extends FeaturePlugin {
  const CourseSelectPlugin();

  static const pluginId = 'course_select';

  @override
  String get id => pluginId;
  @override
  String get name => '抢课';
  @override
  String get description => '选课轮次、余量与自动抢课（直连）';
  @override
  List<String> get dependencies => const [PluginIds.network, PluginIds.tools];

  @override
  List<PluginTool> tools(PluginRegistry registry) => [
        PluginTool(
          icon: Icons.bolt_outlined,
          color: Colors.orange,
          title: '抢课',
          subtitle: () => '选课轮次 / 余量 / 自动抢课',
          open: () => const CourseSelectPage(),
        ),
      ];
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；--dart-define=EXCLUDE_COURSE_SELECT=true 时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(features: [CourseSelectPlugin()]);
