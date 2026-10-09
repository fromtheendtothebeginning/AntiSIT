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
  String get description => '历年成绩与 GPA';
  @override
  List<String> get dependencies => const [PluginIds.network];

  @override
  List<PluginTool> tools(PluginRegistry registry) => [
        PluginTool(
          icon: Icons.fact_check_rounded,
          color: Colors.blue,
          title: '成绩单',
          subtitle: () => '历年成绩与 GPA',
          open: () => const GradesPage(),
        ),
      ];
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_XXX=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [GradesPlugin()]);
