import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'course_cloud_service.dart';

/// 「课程表设置」里的课程通知方式（不通知 / 弹窗 / 流体云）。
///
/// 三选一存在 [AppState.courseNotifyMode]：上课提醒据此跳过课程通知，
/// 流体云模式则由 [CourseCloudService] 把未来 7 天的课程窗口交给原生闹钟。
class CourseNotifyTile extends StatefulWidget {
  const CourseNotifyTile({super.key});

  @override
  State<CourseNotifyTile> createState() => _CourseNotifyTileState();
}

class _CourseNotifyTileState extends State<CourseNotifyTile> {
  FluidCloudInfo? _info;

  FluidCloudCapability? get _capability =>
      PluginRegistry.I.capability<FluidCloudCapability>(PluginIds.fluidCloud);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final info = await _capability?.info();
    if (mounted) setState(() => _info = info);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final mode = AppState.I.courseNotifyMode;
        final parts = [
          CourseNotifyMode.label(mode),
          if (mode == CourseNotifyMode.cloud && _info != null) _info!.label,
        ];
        return ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('课程通知方式'),
          subtitle: Text(parts.join(' · '), style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openSheet,
        );
      },
    );
  }

  Future<void> _openSheet() async {
    var info = _info;
    if (info == null) {
      info = await _capability?.info();
      if (mounted) setState(() => _info = info);
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // 内容比半屏高（选项 + 预览卡 + 预览按钮）：允许拉高并整体滚动，
      // 否则最下面的按钮会顶出屏幕、点不到。
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.86,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('课程通知方式',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Text('由「流体云课程通知」接管课程提醒；日程与考试提醒仍走「上课提醒」。',
                  style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6)),
              const SizedBox(height: 4),
              _option(ctx, CourseNotifyMode.none, '不通知', '课前不再提醒'),
              _option(ctx, CourseNotifyMode.popup, '弹窗通知', '课前 $leadMinutes 分钟系统通知（原上课提醒）'),
              _option(ctx, CourseNotifyMode.cloud, '流体云通知',
                  '课前 $leadMinutes 分钟亮起常驻倒计时，下课前收起'),
              const SizedBox(height: 10),
              const _FluidCloudPreview(),
              if (info != null && !info.isKnownVendor)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '未识别到 ColorOS / OriginOS / 荣耀 MagicOS / 澎湃OS：流体云会以普通常驻通知显示。',
                    style: TextStyle(fontSize: 11, color: SemColors.textMuted, height: 1.5),
                  ),
                )
              else if (info != null && !info.promotedSupported)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '当前系统是 Android ${info.apiLevel}：流体云会以常驻倒计时通知显示，'
                    'Android 16+ 才会交给系统升格。',
                    style: TextStyle(fontSize: 11, color: SemColors.textMuted, height: 1.5),
                  ),
                ),
              if (info != null && info.isKnownVendor && info.promotedSupported)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '已识别 ${info.label}（Android ${info.apiLevel}）：将由系统按流体云 / 原子通知 / 焦点通知 / 灵动胶囊展示。',
                    style: TextStyle(fontSize: 11, color: SemColors.textMuted, height: 1.5),
                  ),
                ),
              if (info != null && info.vendor == 'coloros')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'ColorOS 的真实流体云形态需要 OPPO 泛在服务卡片（UPK）接入；当前按系统实时通知呈现。',
                    style: TextStyle(fontSize: 11, color: SemColors.textMuted, height: 1.5),
                  ),
                ),
              if (info != null && !info.notificationsEnabled)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('通知权限未开启：流体云不会显示，请到系统设置里允许 AntiSIT 发通知。',
                      style: TextStyle(fontSize: 11, color: SemColors.danger, height: 1.5)),
                ),
              if (info != null && info.notificationsEnabled && !info.exactAlarm)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('精确闹钟未授权：后台到点亮起 / 收起可能延迟，可在系统设置里允许「闹钟与提醒」。',
                      style: TextStyle(fontSize: 11, color: SemColors.warning, height: 1.5)),
                ),
              if (AppState.I.courseNotifyMode == CourseNotifyMode.cloud) ...[
                const Divider(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final ok = await CourseCloudService.I.preview();
                      if (!ctx.mounted) return;
                      // 预览失败最常见的是通知权限没开 / 渠道被系统关了，直接说清楚
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text(ok
                            ? '已发送预览通知，1 分钟后自动收起'
                            : '预览发送失败：请允许 AntiSIT 发送通知后重试'),
                        behavior: SnackBarBehavior.floating,
                      ));
                    },
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: const Text('预览流体云通知（1 分钟）'),
                  ),
                ),
              ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    unawaited(_load());
  }

  Widget _option(BuildContext context, String value, String title, String subtitle) {
    final selected = AppState.I.courseNotifyMode == value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontSize: 14.5)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11.5)),
      trailing: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        size: 20,
        color: selected ? SemColors.accent : SemColors.textMuted,
      ),
      onTap: () async {
        Navigator.pop(context);
        await CourseCloudService.I.setMode(value);
      },
    );
  }
}

/// 课前 lead 分钟（与 [CourseCloudService.leadMinutes] 同一个数，文案里用）。
const int leadMinutes = CourseCloudService.leadMinutes;

/// 流体云卡片预览：按成熟实时状态卡片的信息层级画一遍
/// （胶囊态：课程 + 剩余时间；展开态：状态 → 课程 → 地点/时间 → 进度）。
///
/// 只用于设置面板里看设计；真实样式由系统（ColorOS / OriginOS / 澎湃OS）决定。
class _FluidCloudPreview extends StatelessWidget {
  const _FluidCloudPreview();

  static int _minutes(String hhmm) {
    final p = hhmm.split(':');
    return (int.tryParse(p.first) ?? 0) * 60 +
        (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final today = TimetableStore.todayCourses(now: now);
    _TtSlot? current;
    _TtSlot? upcoming;
    for (final c in today) {
      final start = _minutes(c.start);
      final end = _minutes(c.end);
      if (start <= nowMin && nowMin < end && current == null) {
        current = _TtSlot(c.name, c.place, start, end);
      } else if (start > nowMin && upcoming == null) {
        upcoming = _TtSlot(c.name, c.place, start, end);
      }
    }
    final hero = current ?? upcoming ??
        const _TtSlot('高等数学', '二教E101', 10 * 60 + 15, 10 * 60 + 55);
    final isCurrent = current != null;
    final remaining = isCurrent ? (hero.end - nowMin).clamp(0, 24 * 60) : leadMinutes;
    final nearEnd = isCurrent && remaining <= 15;
    // 系统里的倒计时会跳，这里统一直给「大概时间」；最后 15 分钟固定一句话
    final status = nearEnd
        ? '还有十五分钟下课'
        : isCurrent
            ? '上课中 · ${_hhmm(hero.end)} 下课'
            : upcoming != null
                ? '${hero.start - nowMin} 分钟后上课'
                : '下一节课';
    final range = '${_hhmm(hero.start)}–${_hhmm(hero.end)}';
    _TtSlot? next;
    for (final c in today) {
      final start = _minutes(c.start);
      if (start < hero.end) continue;
      if (next == null || start < next.start) {
        next = _TtSlot(c.name, c.place, start, _minutes(c.end));
      }
    }
    final nextText = next == null
        ? null
        : (next.place.isEmpty
            ? '下节 ${next.name}'
            : '下节 ${next.place} · ${next.name}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('流体云预览',
                style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
            const Spacer(),
            Text('实际样式由系统决定',
                style: TextStyle(fontSize: 10, color: SemColors.textMuted)),
          ],
        ),
        const SizedBox(height: 6),
        // 展开态
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          // 和 App 内的玻璃卡一致：卡面 + 细边框，不用深色渐变
          decoration: BoxDecoration(
            color: SemColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: SemColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isCurrent ? SemColors.accent : SemColors.neutralSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isCurrent ? Colors.white : SemColors.textMuted,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(range,
                      style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                ],
              ),
              const SizedBox(height: 8),
              Text(hero.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, height: 1.2)),
              const SizedBox(height: 2),
              Text(
                hero.place.isEmpty ? '地点待定' : hero.place,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: SemColors.textSecondary),
              ),
              if (nextText != null) ...[
                const SizedBox(height: 8),
                Divider(height: 1, color: SemColors.border),
                const SizedBox(height: 6),
                Text(nextText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    isCurrent ? '${_hhmm(hero.end)} 下课' : '${_hhmm(hero.start)} 上课',
                    style: TextStyle(fontSize: 10.5, color: SemColors.textMuted),
                  ),
                  const Spacer(),
                  // 底部信息（OPPO 组合模板的 trailing）：只放一个操作
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: SemColors.accentSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('查看课表 ›',
                        style: TextStyle(fontSize: 10.5, color: SemColors.accent)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 胶囊态（状态栏 / 灵动岛那一行）
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
            decoration: BoxDecoration(
              color: SemColors.textPrimary,
              borderRadius: BorderRadius.circular(999),
            ),
            // 上岛排版：摄像头左边课程名、右边地点
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_month_outlined,
                      size: 13, color: isCurrent ? SemColors.accent : SemColors.warning),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(hero.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: SemColors.bg)),
                  ),
                  if (hero.place.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(hero.place,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: SemColors.bg)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}

class _TtSlot {
  const _TtSlot(this.name, this.place, this.start, this.end);
  final String name;
  final String place;
  final int start;
  final int end;
}
