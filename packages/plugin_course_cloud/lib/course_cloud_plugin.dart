import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'course_cloud_service.dart';
import 'course_notify_tile.dart';

/// 流体云课程通知：在「流体云」能力与「课程表」之上接管课程提醒。
/// 课程通知三选一（不通知 / 弹窗通知 / 流体云通知）收在课程表设置里；
/// 流体云通知课前亮起、常驻倒计时、下课前收起，排期交给原生闹钟，App 被杀也按时生效。
class CourseCloudPlugin extends FeaturePlugin {
  const CourseCloudPlugin();

  static const pluginId = PluginIds.courseCloud;

  @override
  String get id => pluginId;
  @override
  String get name => '流体云课程通知';
  @override
  String get description => '课程通知三选一：不通知 / 弹窗通知 / 流体云通知（依赖课程表与流体云）';
  @override
  bool get defaultEnabled => false;
  @override
  List<String> get dependencies => const [PluginIds.timetable, PluginIds.fluidCloud];

  /// 上课提醒是可选的：在就让它按新模式重排；不在就只有流体云这一路。
  @override
  List<String> get optionalDependencies => const [PluginIds.reminder];
  @override
  int get settingsOrder => 45;

  @override
  Future<void> init() async {
    // 回到前台时也对一次：过期窗口清掉、正在上的课补亮（闹钟被系统压掉时的兜底）。
    CourseCloudService.I.attach();
    // 启动时按当前模式对一次排期（幂等）。
    unawaited(CourseCloudService.I.sync());
  }

  /// 课程通知方式是课表设置的一部分，收在「课程表设置」二级页里。
  @override
  List<Widget> timetableSettingsTiles(BuildContext context, PluginRegistry registry) =>
      const [CourseNotifyTile()];
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；能力「课表保存后重排流体云」挂在
/// PluginIds.courseCloud 上（TimetableStore 按 id 取用）；EXCLUDE_COURSE_CLOUD 为真时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(
  features: [CourseCloudPlugin()],
  capabilities: {PluginIds.courseCloud: CourseCloudSyncImpl()},
);
