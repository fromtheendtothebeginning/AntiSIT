import 'package:flutter/material.dart';

import 'feedback_page.dart';
import 'package:campus_core/campus_core.dart';

/// 提交反馈：Issue / PR / Fork 三种方式的 GitHub 入口（无依赖，删掉不影响任何功能）。
class FeedbackPlugin extends FeaturePlugin {
  const FeedbackPlugin();

  static const pluginId = 'feedback';

  @override
  String get id => pluginId;
  @override
  String get name => '提交反馈';
  @override
  String get description => 'Issue · PR · Fork（GPL-3.0）三个 GitHub 入口';
  @override
  int get settingsOrder => 70;

  @override
  List<Widget> settingsTiles(BuildContext context, PluginRegistry registry) => [
        ListTile(
          leading: const Icon(Icons.feedback_outlined),
          title: const Text('提交反馈'),
          subtitle: const Text('Issue · PR · Fork · GitHub（GPL-3.0）', style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const FeedbackPage())),
        ),
      ];
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_XXX=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [FeedbackPlugin()]);
