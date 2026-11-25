import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'credit_math.dart';
import 'score_widgets.dart';

/// 「分数概览」页：学生信息行 + 总分 / 实践学分 + 分组手风琴（带达标胶囊）。
Widget buildScoreOverview({
  required double topInset,
  required double tabsRowHeight,
  required Map<String, dynamic>? data,
  required ScoreTargetPolicy policy,
  required bool loading,
  required String? error,
  required bool fromCache,
  required bool refreshFailed,
  required Future<void> Function() onRefresh,
}) {
  final groups = ((data?['groups'] as List?) ?? const [])
      .cast<Map<String, dynamic>>();
  final total = asNum(data?['total']);
  final empty = total == null && groups.isEmpty;

  return PageStateView(
    loading: loading && data == null,
    error: error,
    empty: !loading && error == null && empty,
    emptyText: '暂无第二课堂数据，请稍后重试',
    onRetry: onRefresh,
    child: RefreshIndicator(
      // 刷新圈落在悬浮切换器下面，别贴着屏幕最上沿（issue #14）
      edgeOffset: topInset + tabsRowHeight,
      onRefresh: onRefresh,
      child: ListView(
        // 记住本页滚动位置：切走再切回来仍停在原处
        key: const PageStorageKey<String>('score_overview'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          12,
          8 + topInset + tabsRowHeight,
          12,
          20,
        ),
        children: [
          ToolRefreshBar(
            refreshing: loading,
            fromCache: fromCache,
            failed: refreshFailed,
            onRefresh: onRefresh,
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data != null) _studentLine(data),
                if (data != null && policy.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '本年级达标线尚未配置，仅显示实际分数',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: SemColors.textMuted,
                      ),
                    ),
                  ),
                if (data != null && total != null) ...[
                  const SizedBox(height: 14),
                  _stats(data, total, policy),
                  const SizedBox(height: 16),
                ],
                for (var gi = 0; gi < groups.length; gi++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _groupTile(groups[gi], gi, groups.length, policy),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// 学生信息行（学号 / 姓名 / 年级 / 学院 / 专业 / 班级，中点分隔）。
Widget _studentLine(Map<String, dynamic> data) {
  final s = data['student'] as Map<String, dynamic>? ?? {};
  final parts = <String>[
    if ((s['xh'] ?? '').toString().isNotEmpty) '学号 ${s['xh']}',
    if ((s['xm'] ?? '').toString().isNotEmpty) '姓名 ${s['xm']}',
    if ((s['nj'] ?? '').toString().isNotEmpty) '年级 ${s['nj']}',
    if ((s['bmmc'] ?? '').toString().isNotEmpty) '${s['bmmc']}',
    if ((s['zymc'] ?? '').toString().isNotEmpty) '${s['zymc']}',
    if ((s['bjmc'] ?? '').toString().isNotEmpty) '${s['bjmc']}',
  ];
  return Text(
    parts.join('  ·  '),
    style: TextStyle(
      fontSize: 12,
      color: SemColors.textSecondary,
      height: 1.6,
    ),
  );
}

/// 总得分 / 实践学分两个大数字；实践学分带 CountUp 与达标着色。
Widget _stats(
  Map<String, dynamic> data,
  num total,
  ScoreTargetPolicy policy,
) {
  final credit = asNum(data['credit']);
  final target = policy.total;
  final reached = target != null && credit != null && credit >= target;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '总得分',
            style: TextStyle(fontSize: 11, color: SemColors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            '$total',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              height: 1.1,
              color: SemColors.textPrimary,
            ),
          ),
        ],
      ),
      const SizedBox(width: 28),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '实践学分',
            style: TextStyle(fontSize: 11, color: SemColors.textMuted),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              ScoreCountUpText(
                value: credit?.toDouble(),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  color: target == null || credit == null
                      ? SemColors.textPrimary
                      : (reached ? SemColors.success : SemColors.danger),
                ),
              ),
              if (target != null) ...[
                const SizedBox(width: 4),
                Text(
                  '/ ${formatCredit(target)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: SemColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    ],
  );
}

/// 一个分组：无展开需求（美育 / 健康教育）的平铺一行，其余用可展开手风琴。
Widget _groupTile(
  Map<String, dynamic> group,
  int gi,
  int groupCount,
  ScoreTargetPolicy policy,
) {
  final target = policy.groupFor('${group['name'] ?? ''}');
  final actual = asNum(group['subtotal']);
  final targetVal = target?.target;
  final rowsCount = ((group['rows'] as List?) ?? const []).length;

  if (target != null && target.noExpand) {
    return Container(
      decoration: _groupDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Expanded(child: _groupName('${group['name']}')),
          if (actual != null) _groupCapsule(actual, targetVal),
        ],
      ),
    );
  }

  return ScoreGroupTile(
    name: '${group['name'] ?? ''}',
    actual: actual,
    targetVal: targetVal,
    policy: policy,
    rows: ((group['rows'] as List?) ?? const []).cast<Map<String, dynamic>>(),
    defaultOpen: gi < groupCount - 2 && rowsCount <= 4,
  );
}

BoxDecoration _groupDecoration() => BoxDecoration(
      color: SemColors.stripe,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: SemColors.border),
    );

Widget _groupName(String name) => Text(
      name,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: SemColors.textPrimary,
      ),
    );

/// 组达标胶囊：默认蓝；有目标时达标绿 / 未达标红。
Widget _groupCapsule(num actual, double? targetVal) {
  final reached = targetVal != null && actual >= targetVal;
  final color = targetVal == null
      ? SemColors.accent
      : (reached ? SemColors.success : SemColors.danger);
  return Capsule(
    targetVal != null
        ? '${formatCredit(actual)} / ${formatCredit(targetVal)}'
        : formatCredit(actual),
    color: color,
    soft: targetVal == null
        ? SemColors.accentSoft
        : (reached ? SemColors.successSoft : SemColors.dangerSoft),
  );
}

/// 可展开分组（受控手风琴，复刻 cs-group-summary / cs-group-body）。
class ScoreGroupTile extends StatefulWidget {
  const ScoreGroupTile({
    super.key,
    required this.name,
    required this.actual,
    required this.targetVal,
    required this.policy,
    required this.rows,
    required this.defaultOpen,
  });

  final String name;
  final num? actual;
  final double? targetVal;
  final ScoreTargetPolicy policy;
  final List<Map<String, dynamic>> rows;
  final bool defaultOpen;

  @override
  State<ScoreGroupTile> createState() => _ScoreGroupTileState();
}

class _ScoreGroupTileState extends State<ScoreGroupTile> {
  late bool _open = widget.defaultOpen;

  @override
  Widget build(BuildContext context) {
    final actual = widget.actual;
    final targetVal = widget.targetVal;
    final reached = actual != null && targetVal != null && actual >= targetVal;
    final color = targetVal == null
        ? SemColors.accent
        : (reached ? SemColors.success : SemColors.danger);

    return Container(
      decoration: BoxDecoration(
        color: SemColors.stripe,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SemColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: SemColors.textPrimary,
                      ),
                    ),
                  ),
                  if (actual != null) ...[
                    Capsule(
                      targetVal != null
                          ? '${formatCredit(actual)} / ${formatCredit(targetVal)}'
                          : formatCredit(actual),
                      color: color,
                      soft: targetVal == null
                          ? SemColors.accentSoft
                          : (reached
                              ? SemColors.successSoft
                              : SemColors.dangerSoft),
                    ),
                    const SizedBox(width: 8),
                  ],
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.arrow_drop_down,
                      size: 20,
                      color: SemColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeOut,
            crossFadeState:
                _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: SemColors.border)),
              ),
              child: widget.rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '暂无第二课堂数据，请稍后重试',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: SemColors.textMuted,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < widget.rows.length; i++)
                          _miniRow(widget.rows[i], i == widget.rows.length - 1),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 二级行：名称左、值右对齐加粗；有子目标时绿 / 红着色。
  Widget _miniRow(Map<String, dynamic> row, bool last) {
    final name = '${row['name'] ?? ''}';
    final subTarget = widget.policy.subFor(name);
    final hasTarget = subTarget != null;
    final value = asNum(row['value']);
    final raw = row['value'];
    final reached = hasTarget && value != null && value >= subTarget;
    final valueColor = hasTarget
        ? (reached ? SemColors.success : SemColors.danger)
        : SemColors.textPrimary;
    final valueText = value != null
        ? formatCredit(value)
        : ((raw == null || raw.toString().isEmpty) ? '—' : '$raw');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: SemColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(fontSize: 13, color: SemColors.textSecondary),
            ),
          ),
          Text(
            hasTarget ? '$valueText / ${formatCredit(subTarget)}' : valueText,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
