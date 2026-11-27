import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'package:campus_core/campus_core.dart';

/// 后台定时任务的唯一入口：由 main() 注册成一个常驻的 WorkManager 任务。
///
/// 只在 Android 上真正跑（iOS 的周期任务由系统按使用习惯调度，本项目没发 iOS 包）；
/// 桌面端没有 WorkManager，注册与检查都直接跳过。
const String activityWatchTaskName = 'antisit.activity_watch';
const String activityWatchUniqueName = 'antisit.activity_watch';

/// 每小时间隔（系统允许的最小值是 15 分钟，我们按需求取 1 小时）。
const Duration activityWatchInterval = Duration(hours: 1);

/// 后台调度是否可用：真机 Android 才有 WorkManager，测试与桌面端一律不装。
bool get backgroundTasksSupported => !kIsWeb && Platform.isAndroid;

/// WorkManager 的回调调度器：必须放在顶层并打上 entry-point 标注，
/// 后台 isolate 靠回调句柄找到它（不能做成闭包，闭包进不了后台进程）。
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != activityWatchTaskName) return true;
    try {
      final summary = await runActivityWatchInBackground();
      debugPrint('[后台] 二课活动检查：$summary');
      return true;
    } catch (e, s) {
      // 返回 true：这是业务失败（网络 / 未登录），不该让系统无限重试同一轮。
      debugPrint('[后台] 二课活动检查失败：$e\n$s');
      return true;
    }
  });
}

/// 启动时注册（幂等）：开关关着也注册，这样用户什么时候打开开关都有人执行；
/// 真正的「要不要联网」由 ActivityWatchService.check 自己判断（省电、省隧道）。
Future<void> startBackgroundTasks() async {
  if (!backgroundTasksSupported) return;
  try {
    await Workmanager().initialize(backgroundCallbackDispatcher);
    await Workmanager().registerPeriodicTask(
      activityWatchUniqueName,
      activityWatchTaskName,
      frequency: activityWatchInterval,
      initialDelay: const Duration(minutes: 3),
      constraints: Constraints(requiresBatteryNotLow: true),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
    final minutes = activityWatchInterval.inMinutes.toString();
    debugPrint('[后台] 二课活动检查已注册：每 $minutes 分钟一次');
  } catch (e) {
    debugPrint('[后台] 注册定时任务失败：$e');
  }
}

/// 用户关掉提醒时可以直接撤掉排期（保留着也无所谓：检查逻辑自己会短路）。
Future<void> stopBackgroundTasks() async {
  if (!backgroundTasksSupported) return;
  try {
    await Workmanager().cancelByUniqueName(activityWatchUniqueName);
  } catch (e) {
    debugPrint('[后台] 撤销定时任务失败：$e');
  }
}