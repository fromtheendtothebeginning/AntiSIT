import 'package:flutter/foundation.dart';

import 'package:campus_core/campus_core.dart';

import 'class_reminder_service.dart';

/// 上课提醒能力实现：把本包的 [ClassReminderService] 暴露给课表页（铃铛）与课表存储（重排期）。
/// 消费方只拿到 campus_core 的 [ReminderCapability] 接口；本插件停用时注册表查不到 → 铃铛消失、不再排期。
class ReminderCapabilityImpl implements ReminderCapability {
  const ReminderCapabilityImpl();

  ClassReminderService get _s => ClassReminderService.I;

  @override
  Listenable get listenable => _s;

  @override
  bool get enabled => _s.enabled;

  @override
  int get leadMinutes => ClassReminderService.leadMinutes;

  @override
  Future<void> loadEnabled() => _s.loadEnabled();

  @override
  Future<void> reschedule() => _s.reschedule();

  @override
  Future<String?> enable() => _s.enable();

  @override
  Future<void> disable() => _s.disable();
}
