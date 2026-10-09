import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

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
      '课前 ${ClassReminderService.leadMinutes} 分钟后台通知，不用打开 App；依赖课程表里的上课时间';
  @override
  List<String> get dependencies => const [PluginIds.timetable];
  @override
  int get settingsOrder => 40;

  @override
  Future<void> init() async {
    await ClassReminderService.I.loadEnabled();
    // 排期要初始化通知插件再排最多 64 条定时通知，别挡着进主页
    unawaited(_rescheduleQuietly());
  }

  static Future<void> _rescheduleQuietly() async {
    try {
      await ClassReminderService.I.reschedule();
    } catch (e) {
      debugPrint('[上课提醒] 启动排期失败：$e');
    }
  }

  @override
  List<Widget> settingsTiles(BuildContext context, PluginRegistry registry) =>
      const [_ReminderTile()];
}

/// 开关 + 自检。开关状态由 [ClassReminderService] 自己持有；
/// 打开后额外显示「通知 / 精确闹钟 / 后台」三项状态，哪项不对点哪项去系统里开。
class _ReminderTile extends StatefulWidget {
  const _ReminderTile();

  @override
  State<_ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends State<_ReminderTile> {
  /// 打开时申请通知权限（必要时再要精确闹钟权限）并按当前课表排期；
  /// 开关状态由服务自己 notifyListeners，这里不用 setState。
  Future<void> _toggle(bool v) async {
    final messenger = ScaffoldMessenger.of(context);
    String? tip;
    if (v) {
      tip = await ClassReminderService.I.enable();
    } else {
      await ClassReminderService.I.disable();
      tip = '已关闭上课提醒';
    }
    if (!mounted || tip == null) return;
    messenger.showSnackBar(SnackBar(content: Text(tip), behavior: SnackBarBehavior.floating));
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
              svc.enabled
                  ? '课前 ${ClassReminderService.leadMinutes} 分钟通知（无需打开 App，重启后仍有效）'
                  : '课前 ${ClassReminderService.leadMinutes} 分钟通知，后台也能收到',
              style: const TextStyle(fontSize: 12),
            ),
            value: svc.enabled,
            onChanged: _toggle,
          ),
          if (svc.enabled) const _ReminderHealthBox(),
        ],
      ),
    );
  }
}

/// 提醒自检：把「系统层面还差什么」直接摆出来，并给一键去设置的入口。
///
/// 为什么要它：排期成功不等于能弹出来——通知权限、精确闹钟、厂商省电策略
/// （小米/华为/OPPO/vivo 尤其激进）任意一项不对，用户那边都是「提醒不来」，
/// 而这三项都只有系统设置页能改。
class _ReminderHealthBox extends StatefulWidget {
  const _ReminderHealthBox();

  @override
  State<_ReminderHealthBox> createState() => _ReminderHealthBoxState();
}

class _ReminderHealthBoxState extends State<_ReminderHealthBox> with WidgetsBindingObserver {
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

  /// 用户从系统设置页回来时重查一次，改没改得掉看得见。
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
    if (h == null) {
      // 用文字而不是转圈：设置项里的自检不需要占一行动画，也让测试能 pumpAndSettle
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Text('自检中…',
            style: TextStyle(fontSize: 11.5, color: SemColors.textMuted)),
      );
    }

    final rows = <Widget>[];
    if (h.notifications != null) {
      rows.add(_StatusRow(
        ok: h.notifications == true,
        label: '通知权限',
        value: h.notifications == true ? '已允许' : '未允许：提醒根本弹不出来',
        action: h.notifications == true ? null : ('去开启', ClassReminderService.I.openNotificationSettings),
      ));
    }
    if (h.exactAlarm != null) {
      rows.add(_StatusRow(
        ok: h.exactAlarm == true,
        label: '精确闹钟',
        value: h.exactAlarm == true ? '已允许，准点提醒' : '未允许：只能不精确触发，可能晚几分钟',
        action: h.exactAlarm == true
            ? null
            : ('去允许', ClassReminderService.I.openExactAlarmSettings),
      ));
    }
    if (h.batteryUnrestricted != null) {
      rows.add(_StatusRow(
        ok: h.batteryUnrestricted == true,
        label: '后台运行',
        value: h.batteryUnrestricted == true
            ? '已排除电池优化'
            : '受省电策略限制：后台可能被掐掉，提醒不来',
        action: h.batteryUnrestricted == true ? null : ('去设置', _openBattery),
      ));
    }
    rows.add(_StatusRow(
      ok: h.planned > 0,
      label: '已排提醒',
      value: h.planned > 0
          ? '未来 ${ClassReminderService.horizonDays} 天 ${h.planned} 条'
          : '按当前课表暂时没有要提醒的课',
      muted: h.planned == 0,
    ));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...rows,
          const SizedBox(height: 6),
          Text(
            h.allGood
                ? '三项都正常，提醒会在课前 ${ClassReminderService.leadMinutes} 分钟弹出。'
                : '小米 / 华为 / OPPO / vivo 等机型还要在「应用信息 → 电池 / 省电策略 / 自启动」里放开限制，'
                    '（或者把 App 锁在后台）提醒才稳定。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: h.allGood ? SemColors.textMuted : SemColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  /// 电池优化列表页；有些 ROM 没有这个页，退到应用信息页（省电策略在那儿）。
  Future<void> _openBattery() async {
    final ok = await ClassReminderService.I.openBatterySettings();
    if (!ok) await ClassReminderService.I.openAppInfoSettings();
  }
}

/// 一行状态：左边圆点表示好不好，右边可选一个「去开启」动作。
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
    final color = muted
        ? SemColors.textMuted
        : (ok ? SemColors.success : SemColors.danger);
    final done = action;
    return InkWell(
      onTap: done == null ? null : () => done.$2(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 14, color: color),
            const SizedBox(width: 8),
            SizedBox(
              width: 60,
              child: Text(label,
                  style: TextStyle(fontSize: 12, color: SemColors.textSecondary)),
            ),
            Expanded(
              child: Text(value, style: TextStyle(fontSize: 12, color: color, height: 1.35)),
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

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_XXX=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [ReminderPlugin()]);
