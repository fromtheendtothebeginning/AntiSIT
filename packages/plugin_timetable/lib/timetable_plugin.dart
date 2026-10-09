import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';
import 'timetable_page.dart';

/// 课程表：周 / 日视图、教务与考试导入、调休规则、学期设置（底栏第 1 页）。
class TimetablePlugin extends FeaturePlugin {
  const TimetablePlugin();

  static const pluginId = 'timetable';

  @override
  String get id => pluginId;
  @override
  String get name => '课程表';
  @override
  String get description => '周 / 日视图、教务与考试导入、调休规则、学期起止设置';
  @override
  List<String> get dependencies => const [PluginIds.network];
  /// AI 只用来「识别校历截图 / 自动过验证码」，没配就是人工输入，不算硬依赖。
  @override
  List<String> get optionalDependencies => const [PluginIds.ai];
  @override
  int get settingsOrder => 45;

  @override
  List<PluginNavItem> navItems(registry, tab) => [
        PluginNavItem(
          icon: Icons.calendar_month_outlined,
          activeIcon: Icons.calendar_month,
          label: '课程表',
          order: 10,
          build: (_) => const TimetablePage(),
        ),
      ];

  @override
  List<Widget> settingsTiles(BuildContext context, registry) => [
        SwitchListTile(
          secondary: const Icon(Icons.visibility_off_outlined),
          title: const Text('上完的课淡化显示'),
          subtitle: const Text('关闭后已上完的课与普通课一样显示正常彩色（需已设学期起点）',
              style: TextStyle(fontSize: 12)),
          value: AppState.I.dimCompleted,
          onChanged: (v) => AppState.I.setDimCompleted(v),
        ),
      ];
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_XXX=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [TimetablePlugin()]);
