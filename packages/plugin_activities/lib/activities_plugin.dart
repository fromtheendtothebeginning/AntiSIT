import 'package:flutter/material.dart';

import 'activities_capability_impl.dart';
import 'activities_page.dart';
import 'activity_watch_settings_page.dart';
import 'package:campus_core/campus_core.dart';

/// 二课活动：报名状态看板、关键词搜索、排序。
class ActivitiesPlugin extends FeaturePlugin {
  const ActivitiesPlugin();

  static const pluginId = 'activities';

  @override
  String get id => pluginId;
  @override
  String get name => '二课活动';
  @override
  String get description => '第二课堂活动：报名状态、时间名额与在线报名';
  @override
  List<String> get dependencies => const [PluginIds.network, PluginIds.tools];

  /// 扫一扫是软依赖：活动页右上角的扫码入口有就用、没有就不显示。
  @override
  List<String> get optionalDependencies => const [PluginIds.scan];

  @override
  int get settingsOrder => 52;

  /// 新活动提醒属于长期偏好，入口收在「我的 → 配置」页。
  @override
  List<Widget> configTiles(BuildContext context, PluginRegistry registry) => [
    ListTile(
      leading: const Icon(Icons.notifications_active_outlined),
      title: const Text('二课新活动提醒'),
      subtitle: Text(
        ActivityWatchService.I.enabled
            ? '已开启 · 选中分类出现新活动时弹通知'
            : '按分类提醒新的第二课堂活动',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ActivityWatchSettingsPage()),
      ),
    ),
  ];

  @override
  List<PluginTool> tools(PluginRegistry registry) => [
    PluginTool(
      icon: Icons.local_activity_outlined,
      color: Colors.purple,
      title: '二课活动',
      subtitle: () => '第二课堂活动：报名状态、时间名额与在线报名',
      open: () => const ActivitiesPage(),
    ),
  ];
}

/// 插件包入口：清单生成器按包名登记；EXCLUDE_ACTIVITIES 开关为真时整包被摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(
  features: [ActivitiesPlugin()],
  // 活动详情页也对外：扫码插件扫到活动码时按能力取用，不 import 本包
  capabilities: {PluginIds.activities: ActivitiesCapabilityImpl()},
);
