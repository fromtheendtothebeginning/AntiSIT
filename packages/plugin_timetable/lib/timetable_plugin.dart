import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';
import 'timetable_page.dart';
import 'timetable_settings_page.dart';

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

  /// 软依赖 = 可选增强：AI 只用来识别校历截图，上课提醒是课表页 AppBar 那颗铃铛；
  /// 都按 id 从注册表取能力（本包不 import 它们），没装 / 停用时对应入口自动消失。
  @override
  List<String> get optionalDependencies => const [PluginIds.ai, PluginIds.reminder];
  @override
  int get settingsOrder => 45;

  @override
  List<PluginNavItem> navItems(registry, tab) => [
        PluginNavItem(
          icon: Icons.calendar_month_outlined,
          activeIcon: Icons.calendar_month_outlined,
          label: '课程表',
          order: 10,
          // 课表页常驻不销毁：把底栏当前页传进去，切回本页时才知道要复位回本周
          build: (index) => TimetablePage(activeTab: tab, myTab: index),
        ),
      ];

  /// 「我的 → 设置」只留一行入口：课表相关设置都收进「课程表设置」二级页。
  @override
  List<Widget> settingsTiles(BuildContext context, registry) => [
        ListTile(
          leading: const Icon(Icons.event_note_outlined),
          title: const Text('课程表设置'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const TimetableSettingsPage())),
        ),
      ];

  /// 课表自己的设置条目放进那个二级页（提醒插件的条目也投在这里）。
  @override
  List<Widget> timetableSettingsTiles(BuildContext context, registry) => [
        SwitchListTile(
          secondary: const Icon(Icons.visibility_off_outlined),
          title: const Text('上完的课淡化显示'),
          value: AppState.I.dimCompleted,
          onChanged: (v) => AppState.I.setDimCompleted(v),
        ),
      ];
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 保持 const：EXCLUDE 开关为真时整条连同包内代码一起被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [TimetablePlugin()]);
