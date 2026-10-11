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
  /// 软依赖 = 可选增强：AI 只用来「识别校历截图 / 自动过验证码」（没配就人工输入）；
  /// 上课提醒是课表页 AppBar 那颗铃铛（插件没装/停用就整颗不出现、课表照常用）。
  /// 两者都通过注册表按 id 取能力，本包不 import 它们；这里声明是为了让依赖图上的边
  /// 与代码耦合一致——生成器会把 `capability<...>(PluginIds.x)` 扫出来对账。
  @override
  List<String> get optionalDependencies => const [PluginIds.ai, PluginIds.reminder];
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

  /// 「我的 → 设置」里只留一行入口：课表相关的设置都收进「课程表设置」二级页
  /// （课表页 → 更多 → 课程表设置 也能进，两处进的是同一页）。
  @override
  List<Widget> settingsTiles(BuildContext context, registry) => [
        ListTile(
          leading: const Icon(Icons.event_note_outlined),
          title: const Text('课程表设置'),
          subtitle: const Text('学期 / 调休 / 上课提醒 / 上完的课淡化', style: TextStyle(fontSize: 12)),
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
/// 编译期常量开关为真时（--dart-define=EXCLUDE_XXX=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [TimetablePlugin()]);
