import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'activities_state.dart';

/// 一行灰色元信息（单行省略）。
class MetaRow extends StatelessWidget {
  const MetaRow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: SemColors.textMuted),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    ),
  );
}

/// 活动广场卡片：状态 / 类别 / 校区胶囊 + 名称与时间名额。
class ActivityMarketCard extends StatelessWidget {
  const ActivityMarketCard({
    super.key,
    required this.activity,
    required this.onTap,
  });

  /// 活动列表项数据（学校原始字段）。
  final Map<String, dynamic> activity;

  /// 点卡片进入详情。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        radius: 10,
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Capsule(marketStateText(a), color: marketStateColor(a)),
                if (a['backfill'] as bool? ?? false)
                  Capsule('事后补录', color: SemColors.info),
                if (campusTagOf(a).isNotEmpty) Capsule(campusTagOf(a)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${a['name']}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: SemColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            if (categoryTextOf(a).isNotEmpty)
              Text(
                categoryTextOf(a),
                style: TextStyle(
                  fontSize: 12,
                  color: SemColors.textSecondary,
                ),
              ),
            const SizedBox(height: 6),
            MetaRow('主办：${a['host']}  ·  名额：${a['quota'] ?? '—'}'),
            const SizedBox(height: 2),
            MetaRow('活动时间：${shortTimeText(a['start'])} ~ ${shortTimeText(a['end'])}'),
            MetaRow(
              '报名窗口：${shortTimeText(a['bm_start'])} ~ ${shortTimeText(a['bm_end'])}',
            ),
          ],
        ),
      ),
    );
  }
}

/// 「我的报名」卡片：报名状态 + 类别胶囊 + 名称 / 时间 / 地点。
class SignedActivityCard extends StatelessWidget {
  const SignedActivityCard({
    super.key,
    required this.activity,
    required this.onTap,
  });

  /// 已报名活动的列表项数据。
  final Map<String, dynamic> activity;

  /// 点卡片进入详情。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final status = '${a['status_text'] ?? ''}'.trim();
    final cat = categoryTextOf(a);
    final statusColor = switch (status) {
      '已报名' => SemColors.success,
      '报名已满' => SemColors.danger,
      '无需报名' => SemColors.textMuted,
      _ => SemColors.accent,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        radius: 10,
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (status.isNotEmpty) Capsule(status, color: statusColor),
                if (cat.isNotEmpty) Capsule(cat, color: SemColors.accent),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${a['name']}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: SemColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            MetaRow('活动时间：${shortTimeText(a['start'])} ~ ${shortTimeText(a['end'])}'),
            if ('${a['place'] ?? ''}'.trim().isNotEmpty)
              MetaRow('地点：${a['place']}'),
          ],
        ),
      ),
    );
  }
}
