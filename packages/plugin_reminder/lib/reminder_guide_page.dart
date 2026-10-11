import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'class_reminder_service.dart';

/// 上课提醒的二级页：自检结果 + 引导。
///
/// 为什么单独一页：排期成功 ≠ 能弹出来——通知权限、精确闹钟、厂商省电策略任意一项不对，
/// 用户那边都是「提醒不来」，而这三项都只有系统设置页能改。设置列表里塞不下这些解释，
/// 所以开关下面只留一行摘要，详情与一键入口都放这儿。
class ReminderGuidePage extends StatefulWidget {
  const ReminderGuidePage({super.key});

  @override
  State<ReminderGuidePage> createState() => _ReminderGuidePageState();
}

class _ReminderGuidePageState extends State<ReminderGuidePage> with WidgetsBindingObserver {
  ReminderHealth? _health;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从系统设置页回来时重查一次，改没改掉看得见。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final h = await ClassReminderService.I.health();
    if (mounted) setState(() => _health = h);
  }

  @override
  Widget build(BuildContext context) {
    final h = _health;
    return Scaffold(
      appBar: AppBar(title: const Text('上课提醒')),
      body: h == null
          ? Center(
              child: Text('自检中…',
                  style: TextStyle(fontSize: 13, color: SemColors.textMuted)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                _verdict(h),
                const SizedBox(height: 10),
                _sectionTitle('系统权限'),
                AppCard(
                  child: Column(
                    children: [
                      if (h.notifications != null)
                        _StatusRow(
                          ok: h.notifications == true,
                          label: '通知权限',
                          value: h.notifications == true ? '已允许' : '未允许',
                          action: h.notifications == true
                              ? null
                              : ('去开启', ClassReminderService.I.openNotificationSettings),
                        ),
                      if (h.exactAlarm != null)
                        _StatusRow(
                          ok: h.exactAlarm == true,
                          label: '精确闹钟',
                          value: h.exactAlarm == true ? '已允许' : '未允许',
                          action: h.exactAlarm == true
                              ? null
                              : ('去允许', ClassReminderService.I.openExactAlarmSettings),
                        ),
                      if (h.batteryUnrestricted != null)
                        _StatusRow(
                          ok: h.batteryUnrestricted == true,
                          label: '后台运行',
                          value: h.batteryUnrestricted == true ? '不受限' : '受限',
                          action: h.batteryUnrestricted == true ? null : ('去设置', _openBattery),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _sectionTitle('已排提醒'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatusRow(
                        ok: h.planned > 0,
                        muted: h.planned == 0,
                        label: '未来 ${ClassReminderService.horizonDays} 天',
                        value: h.planned > 0 ? '${h.planned} 条' : '无',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '按当前课表排期；打开 App 或修改课表时重新排。',
                        style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _sectionTitle('常见原因'),
                AppCard(
                  child: Text(
                    '· 未允许通知权限：提醒不会出现。\n'
                    '· 未允许精确闹钟：可能在原定时间之后触发。\n'
                    '· 部分机型的省电策略会拦截后台提醒，需在系统设置中允许后台运行。\n'
                    '· 从最近任务划除或强行停止会取消已排提醒，重新打开 App 即恢复。',
                    style: TextStyle(
                        fontSize: 12, color: SemColors.textSecondary, height: 1.75),
                  ),
                ),
              ],
            ),
    );
  }

  /// 顶部结论：一眼知道要不要动手。
  Widget _verdict(ReminderHealth h) => AppCard(
        child: Row(
          children: [
            Icon(
              h.allGood ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              size: 22,
              color: h.allGood ? SemColors.success : SemColors.danger,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h.allGood ? '状态正常' : '${h.issueCount} 项未就绪',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: h.allGood ? SemColors.textPrimary : SemColors.danger),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    h.allGood
                        ? '课前 ${ClassReminderService.leadMinutes} 分钟提醒'
                        : '按下方状态逐项开启',
                    style: TextStyle(fontSize: 12, color: SemColors.textMuted, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Text(title,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: SemColors.textSecondary)),
      );

  /// 电池优化列表页；有些 ROM 没有这个页，退到应用信息页（省电策略在那儿）。
  Future<void> _openBattery() async {
    final ok = await ClassReminderService.I.openBatterySettings();
    if (!ok) await ClassReminderService.I.openAppInfoSettings();
  }
}

/// 一行状态：左边圆点表示好不好，右边可选一个动作。
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.ok,
    required this.label,
    required this.value,
    this.action,
    this.muted = false,
  });

  final bool ok;
  final String label;
  final String value;
  final (String, Future<void> Function())? action;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color =
        muted ? SemColors.textMuted : (ok ? SemColors.success : SemColors.danger);
    final done = action;
    return InkWell(
      onTap: done == null ? null : () => done.$2(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              muted
                  ? Icons.info_outline_rounded
                  : (ok ? Icons.check_circle_rounded : Icons.error_outline_rounded),
              size: 14,
              color: color,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 76,
              child: Text(label,
                  style: TextStyle(fontSize: 12, color: SemColors.textSecondary)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(fontSize: 12, color: color, height: 1.35)),
            ),
            if (done != null) ...[
              const SizedBox(width: 6),
              Text(done.$1,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: SemColors.accent)),
              Icon(Icons.chevron_right, size: 16, color: SemColors.accent),
            ],
          ],
        ),
      ),
    );
  }
}
