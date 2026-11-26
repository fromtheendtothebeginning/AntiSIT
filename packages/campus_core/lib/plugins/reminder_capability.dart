import 'package:flutter/foundation.dart';

import 'capability.dart';

/// 上课提醒能力（提供方：上课提醒插件 `PluginIds.reminder`）。
///
/// 契约只放别的插件真的用得着的口子；通知自检与引导页属于插件自己的 UI。
abstract class ReminderCapability implements PluginCapability {
  /// 开关状态会通知（课表页的铃铛靠它重建）。
  Listenable get listenable;

  bool get enabled;

  /// 课前多少分钟提醒（提示文案用）。
  int get leadMinutes;

  Future<void> loadEnabled();

  /// 按当前课表重排定时通知（课表加载/变更后调）。
  Future<void> reschedule();

  /// 打开提醒；返回给用户看的一句提示（可能提醒系统权限没给）。
  Future<String?> enable();

  /// 关闭提醒（不撤回已排的通知，只是不再重排）。
  Future<void> disable();
}
