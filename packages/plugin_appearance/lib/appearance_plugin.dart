import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'appearance_settings_page.dart';

/// 外观设置：主题、夜间模式（跟随系统 / 浅色 / 深色）、预测式返回动画、
/// 以及「界面是否实时跟着滑块切换」。
///
/// 这些选项原来散在「我的」页里（外观滑块 + 主题入口），收进这个二级页；
/// 做成插件的好处跟别的插件一样：不想要就在宿主 pubspec 里删掉它，
/// 或 `--dart-define=EXCLUDE_APPEARANCE=true` 构建时剔除。
/// 夜间模式与跟随开关的取值本身存在 core 的 [AppState] 里（壳层行为要能读到它们）。
class AppearancePlugin extends FeaturePlugin {
  const AppearancePlugin();

  static const pluginId = 'appearance';

  @override
  String get id => pluginId;
  @override
  String get name => '外观设置';
  @override
  String get description =>
      '主题与夜间模式（跟随系统 / 浅色 / 深色）、界面跟手切换、预测式返回动画';
  @override
  int get settingsOrder => 55; // 课表淡化 45 · 提醒 40 · AI 60 之间

  @override
  List<Widget> settingsTiles(BuildContext context, PluginRegistry registry) {
    final mode = switch (AppState.I.themeMode) {
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
      _ => '跟随系统',
    };
    return [
      ListTile(
        leading: const Icon(Icons.brightness_6_outlined),
        title: const Text('外观'),
        subtitle: Text('${registry.theme.name} · $mode',
            style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const AppearanceSettingsPage())),
      ),
    ];
  }
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_APPEARANCE=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉（主题/跟随开关的值留在 core，不受影响）。
const PluginBundle pluginBundle = PluginBundle(features: [AppearancePlugin()]);
