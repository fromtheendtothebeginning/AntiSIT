import 'package:flutter/foundation.dart';

import 'capability.dart';

/// 上课提醒能力（提供方：上课提醒插件 `PluginIds.reminder`）。
///
/// 课表页的铃铛、以及课表存储「改完课表后重排期」，都通过
/// `PluginRegistry.I.capability<ReminderCapability>(PluginIds.reminder)` 取用；
/// 实现（含通知插件调用、系统设置跳转）留在 plugin_reminder 里。
/// 详细自检（通知权限 / 精确闹钟 / 省电策略）与引导页属于那个插件自己的 UI，
/// 不进这个契约——契约只放「别的插件真的用得着」的那几个口子。
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
