import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'class_reminder_service.dart';
import 'reminder_capability_impl.dart';
import 'reminder_guide_page.dart';

/// 上课提醒：课前 15 分钟的后台本地通知，App 没打开也能收到。
/// 提醒时刻由课表换算出来 → 硬依赖课程表；课程表停用/删除后它也会一起退场。
class ReminderPlugin extends FeaturePlugin {
  const ReminderPlugin();

  static const pluginId = 'reminder';

  @override
  String get id => pluginId;
  @override
  String get name => '上课提醒';
  @override
  String get description =>
      '课前 ${ClassReminderService.leadMinutes} 分钟本地通知，App 不用打开；上课时间取自课程表';
  @override
  List<String> get dependencies => const [PluginIds.timetable];
  @override
  int get settingsOrder => 40;

  @override
  Future<void> init() async {
    await ClassReminderService.I.loadEnabled();
    // 初始化通知插件 + 排最多 64 条定时通知，别挡着进主页。
    unawaited(_rescheduleQuietly());
  }

  static Future<void> _rescheduleQuietly() async {
    try {
      await ClassReminderService.I.reschedule();
    } catch (e) {
      debugPrint('[上课提醒] 启动排期失败：$e');
    }
  }

  /// 提醒是课表的一部分，设置收在「课程表设置」二级页里，不单独占「我的」的一行。
  @override
  List<Widget> timetableSettingsTiles(BuildContext context, PluginRegistry registry) =>
      const [_ReminderTile()];
}

/// 开关 + 一行自检摘要；状态详情与系统设置引导在 [ReminderGuidePage]。
class _ReminderTile extends StatefulWidget {
  const _ReminderTile();

  @override
  State<_ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends State<_ReminderTile> with WidgetsBindingObserver {
  ReminderHealth? _health;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (ClassReminderService.I.enabled) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从二级页 / 系统设置页回来时重查，摘要才是最新的。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ClassReminderService.I.enabled) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final h = await ClassReminderService.I.health();
    if (mounted) setState(() => _health = h);
  }

  /// 打开时申请通知权限（必要时再要精确闹钟权限）并按当前课表排期；
  /// 开关状态由服务自己 notifyListeners，这里不用 setState。
  Future<void> _toggle(bool v) async {
    final messenger = ScaffoldMessenger.of(context);
    String? tip;
    if (v) {
      tip = await ClassReminderService.I.enable();
      await _load(); // 自检摘要这时才出现
    } else {
      await ClassReminderService.I.disable();
      tip = '已关闭上课提醒';
    }
    if (!mounted || tip == null) return;
    messenger.showSnackBar(SnackBar(content: Text(tip), behavior: SnackBarBehavior.floating));
  }

  Future<void> _openGuide() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ReminderGuidePage()));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final svc = ClassReminderService.I;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) => Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('上课提醒'),
            subtitle: Text(
              svc.enabled ? '已开启 · 课前 ${ClassReminderService.leadMinutes} 分钟' : '已关闭',
              style: const TextStyle(fontSize: 12),
            ),
            value: svc.enabled,
            onChanged: _toggle,
          ),
          if (svc.enabled) _guideEntry(),
        ],
      ),
    );
  }

  Widget _guideEntry() {
    final h = _health;
    final issue = h?.firstIssue;
    return ListTile(
      leading: Icon(
        issue == null ? Icons.fact_check_outlined : Icons.error_outline_rounded,
        color: issue == null ? SemColors.accent : SemColors.danger,
      ),
      title: const Text('提醒状态',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(
        h == null
            ? '检查中…'
            : issue == null
                ? '正常 · 未来 ${ClassReminderService.horizonDays} 天 ${h.planned} 条'
                : '$issue（${h.issueCount} 项未就绪）',
        style: TextStyle(
          fontSize: 12,
          color: issue == null ? SemColors.textMuted : SemColors.danger,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _openGuide,
    );
  }
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；能力 key 就是本插件 id，课表页（铃铛）与
/// 课表存储（课表变更后重排期）按「接口 + id」取用，被停用时铃铛消失、不再排期；
/// EXCLUDE_REMINDER 为真时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(
  features: [ReminderPlugin()],
  capabilities: {PluginIds.reminder: ReminderCapabilityImpl()},
);
