import 'package:flutter/widgets.dart';

import 'capability.dart';

/// 二课活动能力：给别的插件（如扫码）打开 App 内的活动详情页。
abstract class ActivitiesCapability extends PluginCapability {
  const ActivitiesCapability();

  /// 打开活动详情页（报名入口在详情页里）。
  /// [activity] 是调用方已捞到的列表元信息，可为空（详情页自己拉说明兜底）。
  Future<void> openDetail(
    BuildContext context, {
    required String id,
    Map<String, dynamic>? activity,
  });
}
