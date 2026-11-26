import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'appearance_settings_page.dart';

/// 外观设置：主题、夜间模式、界面跟手切换、预测式返回动画等二级页入口。
/// 取值本身存在 core 的 [AppState] 里（壳层行为要读到它们）。
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
  int get settingsOrder => 55; // 介于课表 45 与 AI 60 之间。

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

/// 插件包入口：tool/gen_plugins.dart 按包名登记；--dart-define=EXCLUDE_APPEARANCE=true 时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(features: [AppearancePlugin()]);
