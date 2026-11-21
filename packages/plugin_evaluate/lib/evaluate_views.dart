import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'evaluate_model.dart';

/// 评教列表里的纯渲染部件：不碰网络、不碰设置，只吃数据。
///
/// 抽出来是为了**能截图 / 能测**：页面自己那层负责取数，这一层只管长什么样。
class EvaluateSummaryCard extends StatelessWidget {
  const EvaluateSummaryCard({
    super.key,
    required this.summary,
    this.connectionLabel = '',
  });

  final EvalSummary summary;

  /// 右上角那枚「直连 / 校园隧道」小胶囊；空串不显示。
  final String connectionLabel;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('本轮评教',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SemColors.textPrimary)),
              const Spacer(),
              if (connectionLabel.isNotEmpty)
                Capsule(connectionLabel, color: SemColors.accent),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              BigStat(
                  label: '未评',
                  value: s.pending.toString(),
                  color: s.pending > 0 ? SemColors.danger : SemColors.textPrimary),
              const SizedBox(width: 20),
              BigStat(label: '已保存', value: s.saved.toString(), color: SemColors.accent),
              const SizedBox(width: 20),
              BigStat(
                  label: '已提交',
                  value: s.submitted.toString(),
                  color: s.submitted > 0 ? SemColors.success : SemColors.textPrimary),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            s.allDone
                ? '本轮已全部提交，感谢参与评教。'
                : (s.pending == 0
                    ? '共 ${s.total} 门次；都已保存，点「全部提交」把保存的内容交上去。'
                    : '共 ${s.total} 门次；点「全部打分」可以一次给所有老师同分并保存，'
                        '点开每一条还能单独调。全部保存后才能「全部提交」。'),
            style: TextStyle(fontSize: 11.5, height: 1.6, color: SemColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// 一条待评：课程 + 教师 + 状态胶囊。
class EvaluateTargetCard extends StatelessWidget {
  const EvaluateTargetCard({super.key, required this.target, this.onTap});

  final EvalTarget target;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = target;
    final color = t.submitted
        ? SemColors.success
        : (t.saved ? SemColors.accent : SemColors.danger);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: SemColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(t.course,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: SemColors.textPrimary)),
                        ),
                        const SizedBox(width: 8),
                        Capsule(t.statusLabel, color: color),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(t.teacher,
                        style: TextStyle(fontSize: 13, color: SemColors.textSecondary)),
                    if (t.subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(t.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                      ),
                    if (t.time.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(t.time,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: SemColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表主体：汇总卡 + 两个统一操作按钮 + 每条待评。
///
/// 两个按钮用**同一种按钮形式**（FilledButton.tonal），不加粗、不突出其中一个——
/// 一个是「打分」一个是「提交」，重要性交给文案与后续确认去表达。
///
/// 「全部提交」不是「统一打分再提交」：它交的是**已经保存好的那套分**，
/// 所以只有每一条都保存过（或已提交）时才可用，否则置灰并说明差几条。
class EvaluateListView extends StatelessWidget {
  const EvaluateListView({
    super.key,
    required this.targets,
    required this.summary,
    this.connectionLabel = '',
    this.onTapTarget,
    this.onRefresh,
    this.onFillAll,
    this.onSubmitAll,
  });

  final List<EvalTarget> targets;
  final EvalSummary summary;
  final String connectionLabel;
  final void Function(EvalTarget target, int index)? onTapTarget;
  final Future<void> Function()? onRefresh;

  /// 全部打分（写回并保存）。
  final Future<void> Function()? onFillAll;

  /// 全部提交（不可撤销，页面自己负责二次确认）。
  final Future<void> Function()? onSubmitAll;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        EvaluateSummaryCard(summary: summary, connectionLabel: connectionLabel),
        const SizedBox(height: 12),
        if (onFillAll != null && onSubmitAll != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: targets.isEmpty ? null : onFillAll,
                        icon: const Icon(Icons.bolt_outlined, size: 18),
                        label: const Text('全部打分'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        // 「全部提交」只管提交**已保存**的内容，没有另设分数的余地：
                        // 所以只有每一条都保存过（或已提交）时才亮起来
                        onPressed: canSubmitAll(targets) ? onSubmitAll : null,
                        icon: Icon(canSubmitAll(targets)
                            ? Icons.done_all_rounded
                            : Icons.lock_outline_rounded,
                            size: 18),
                        label: const Text('全部提交'),
                      ),
                    ),
                  ],
                ),
                if (notSavedCount(targets) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '还有 ${notSavedCount(targets)} 条没保存：'
                      '「全部提交」交的是已保存的内容，都保存好（可以点「全部打分」）之后按钮才会亮。',
                      style: TextStyle(fontSize: 11.5, height: 1.6, color: SemColors.textMuted),
                    ),
                  ),
              ],
            ),
          ),
        for (var i = 0; i < targets.length; i++)
          EvaluateTargetCard(
            target: targets[i],
            onTap: onTapTarget == null ? null : () => onTapTarget!(targets[i], i),
          ),
        if (targets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Text('没有待评的教学班（本轮评教可能还没开始，或已全部完成）',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: SemColors.textMuted)),
          ),
      ],
    );
    final refresh = onRefresh;
    return refresh == null ? list : RefreshIndicator(onRefresh: refresh, child: list);
  }
}