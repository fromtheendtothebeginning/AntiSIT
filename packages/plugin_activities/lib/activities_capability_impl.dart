import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';

import 'activities_page.dart';

/// [ActivitiesCapability] 的实现：推入本插件的活动详情页。
class ActivitiesCapabilityImpl extends ActivitiesCapability {
  const ActivitiesCapabilityImpl();

  @override
  Future<void> openDetail(
    BuildContext context, {
    required String id,
    Map<String, dynamic>? activity,
  }) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
            builder: (_) => ActivityDetailPage(id: id, activity: activity)),
      );
}
