import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 第二课堂分：精确复刻 anticraft.top 网站排版
/// （单面板：学生信息行 + 总得分/实践学分 CountUp + 分组手风琴带达标胶囊）。
class ScorePage extends StatefulWidget {
  const ScorePage({super.key});

  @override
  State<ScorePage> createState() => _ScorePageState();
}

class _ScorePageState extends State<ScorePage> {
  bool _loading = true;
  String? _err;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final r = await ApiClient.I.score();
      _data = r['data'] as Map<String, dynamic>?;
      AppState.I.studentInfo = _data?['student'] as Map<String, dynamic>?;
      ToolCache.score = _data;
    } catch (e) {
      _err = e is ApiError ? e.message : e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final groups = ((data?['groups'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final total = asNum(data?['total']);
    final empty = total == null && groups.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('第二课堂分')),
      body: PageStateView(
        loading: _loading,
        error: _err,
        empty: !_loading && _err == null && empty,
        emptyText: '暂无第二课堂数据，请稍后重试',
        onRetry: _load,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (data != null) _studentLine(data),
                    if (data != null && total != null) ...[
                      const SizedBox(height: 14),
                      _stats(data, total),
                      const SizedBox(height: 16),
                    ],
                    for (var gi = 0; gi < groups.length; gi++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _groupTile(groups[gi], gi, groups.length),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 学生信息行（cs-student-line：12px，中点分隔）──
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
      style: TextStyle(fontSize: 12, color: SemColors.textSecondary, height: 1.6),
    );
  }

  // ── 总得分 / 实践学分 两个大数字（cs-stats）──
  Widget _stats(Map<String, dynamic> data, num total) {
    final credit = asNum(data['credit']);
    final reached = credit != null && credit >= 8; // TOTAL_TARGET = 8（2025 级）
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('总得分', style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
            const SizedBox(height: 2),
            Text('$total',
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w600, height: 1.1,
                    color: SemColors.textPrimary)),
          ],
        ),
        const SizedBox(width: 28),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('实践学分', style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                _CountUpText(
                  value: credit?.toDouble(),
                  style: TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w600, height: 1.1,
                      color: credit == null
                          ? SemColors.textPrimary
                          : (reached ? SemColors.success : SemColors.danger)),
                ),
                const SizedBox(width: 4),
                Text('/ 8',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700,
                        color: SemColors.textSecondary)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ── 分组（cs-group）：美育/健康教育单行平铺，其余可展开 ──
  Widget _groupTile(Map<String, dynamic> group, int gi, int groupCount) {
    final target = _matchScoreTarget('${group['name'] ?? ''}');
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

    return _ScoreGroupTile(
      name: '${group['name'] ?? ''}',
      actual: actual,
      targetVal: targetVal,
      rows: ((group['rows'] as List?) ?? const []).cast<Map<String, dynamic>>(),
      defaultOpen: gi < groupCount - 2 && rowsCount <= 4,
    );
  }

  BoxDecoration _groupDecoration() => BoxDecoration(
        color: SemColors.stripe,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SemColors.border),
      );

  Widget _groupName(String name) => Text(name,
      style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: SemColors.textPrimary));

  /// 组达标胶囊：默认蓝；有目标时达标绿 / 未达标红（cs-group-sub）。
  Widget _groupCapsule(num actual, double? targetVal) {
    final reached = targetVal != null && actual >= targetVal;
    final color = targetVal == null
        ? SemColors.accent
        : (reached ? SemColors.success : SemColors.danger);
    return Capsule(
      '${_fmtNum(actual)} / ${targetVal != null ? _fmtNum(targetVal) : '—'}',
      color: color,
      soft: targetVal == null
          ? SemColors.accentSoft
          : (reached ? SemColors.successSoft : SemColors.dangerSoft),
    );
  }
}

// ── 达标规则（与网站 SCORE_TARGETS / SUB_TARGETS 一致，2025 级）──

class _Target {
  const _Target(this.target, {this.noExpand = false});
  final double? target;
  final bool noExpand;
}

const Map<List<String>, _Target> _scoreTargets = {
  ['德育']: _Target(3.0),
  ['劳育']: _Target(3.0),
  ['美育']: _Target(1.0, noExpand: true),
  ['健康']: _Target(1.0, noExpand: true),
};

const Map<List<String>, double?> _subTargets = {
  ['讲座', '报告', '讲坛', '沙龙', '主题教育', '团日']: 1.8,
  ['安全教育', '安全']: 0.2,
  ['志愿', '公益']: 1.0,
  ['三创', '竞赛', '论文', '专利', '技能证书', '社团活动']: 1.5,
  ['社会实践', '挂职', '学长导航', '境外交流']: 1.0,
  ['劳动教育', '劳动课堂']: null,
  ['校园文明', '文明寝室']: null,
};

_Target? _matchScoreTarget(String groupName) {
  for (final e in _scoreTargets.entries) {
    if (e.key.any((kw) => groupName.contains(kw))) return e.value;
  }
  return null;
}

double? _matchSubTarget(String rowName) {
  for (final e in _subTargets.entries) {
    if (e.key.any((kw) => rowName.contains(kw))) return e.value;
  }
  return null;
}

// ── 可展开分组（受控手风琴，复刻 cs-group-summary / cs-group-body）──

class _ScoreGroupTile extends StatefulWidget {
  const _ScoreGroupTile({
    required this.name,
    required this.actual,
    required this.targetVal,
    required this.rows,
    required this.defaultOpen,
  });

  final String name;
  final num? actual;
  final double? targetVal;
  final List<Map<String, dynamic>> rows;
  final bool defaultOpen;

  @override
  State<_ScoreGroupTile> createState() => _ScoreGroupTileState();
}

class _ScoreGroupTileState extends State<_ScoreGroupTile> {
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
                    child: Text(widget.name,
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: SemColors.textPrimary)),
                  ),
                  if (actual != null) ...[
                    Capsule(
                      '${_fmtNum(actual)} / ${targetVal != null ? _fmtNum(targetVal) : '—'}',
                      color: color,
                      soft: targetVal == null
                          ? SemColors.accentSoft
                          : (reached ? SemColors.successSoft : SemColors.dangerSoft),
                    ),
                    const SizedBox(width: 8),
                  ],
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.arrow_drop_down,
                        size: 20, color: SemColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeOut,
            crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: SemColors.border)),
              ),
              child: widget.rows.isEmpty
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('暂无第二课堂数据，请稍后重试',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: SemColors.textMuted)),
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

  /// 二级行（cs-mini-table）：名称左、值右对齐加粗；有子目标时绿/红着色。
  Widget _miniRow(Map<String, dynamic> row, bool last) {
    final name = '${row['name'] ?? ''}';
    final subTarget = _matchSubTarget(name);
    final hasTarget = subTarget != null;
    final value = asNum(row['value']);
    final raw = row['value'];
    final reached = hasTarget && value != null && value >= subTarget;
    final valueColor = hasTarget
        ? (reached ? SemColors.success : SemColors.danger)
        : SemColors.textPrimary;
    final valueText = value != null
        ? _fmtNum(value)
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
            child: Text(name,
                style: TextStyle(fontSize: 13, color: SemColors.textSecondary)),
          ),
          Text(
            hasTarget ? '$valueText / ${_fmtNum(subTarget)}' : valueText,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: valueColor),
          ),
        ],
      ),
    );
  }
}

String _fmtNum(num v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

/// 数字增长动画（网站 CountUp：0 → 终值，700ms 缓出；值变化重播）。
class _CountUpText extends StatefulWidget {
  const _CountUpText({required this.value, required this.style});

  final double? value;
  final TextStyle style;

  @override
  State<_CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<_CountUpText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late double? _shown = widget.value;

  @override
  void initState() {
    super.initState();
    if (_shown != null) _c.forward();
  }

  @override
  void didUpdateWidget(covariant _CountUpText old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) {
      _shown = widget.value;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _shown;
    if (v == null) {
      return Text('—', style: widget.style);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic).value;
        final val = v * (1 - math.pow(1 - t, 3));
        return Text(val.toStringAsFixed(1), style: widget.style);
      },
    );
  }
}
