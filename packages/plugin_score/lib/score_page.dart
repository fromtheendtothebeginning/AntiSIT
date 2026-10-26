import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'score_target_settings_page.dart';

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

  /// 达标线按入学年级（nj）取：远端配置/本机自定义优先，未配置时用默认规则。
  ScoreTargetPolicy _policy = const ScoreTargetPolicy();

  /// 当前生效的入学年：教务返回优先，直连模式手填兜底。
  String _cohort = '';

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
      // 达标线配置和分数并发拉：配置走公网、分数走校园链路，互不拖慢。
      final targetsFuture = ScoreTargets.load();
      final r = await ApiClient.I.score();
      final targets = await targetsFuture;
      _data = r['data'] as Map<String, dynamic>?;
      final student = _data?['student'];
      final apiNj = student is Map ? '${student['nj'] ?? ''}'.trim() : '';
      // 直连模式手填的年级优先：学校没回或回的年级不合用时以用户填的为准。
      final manual = AppState.I.direct ? AppState.I.creds.grade.trim() : '';
      _cohort = manual.isNotEmpty ? manual : apiNj;
      _policy = targets.forCohort(_cohort);
      ToolCache.score = ToolCache.scoreOf(_data);
      AppState.I.studentInfo = ToolCache.score?.student;
    } catch (e) {
      _err = e is ApiError ? e.message : e.toString();
      if (mounted) showErr(context, e, title: '成绩加载失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 三级页面：调整本机达标线；返回后重拉分数与策略。
  Future<void> _openTargetSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScoreTargetSettingsPage(cohort: _cohort.isEmpty ? null : _cohort),
    ));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final groups = ((data?['groups'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final total = asNum(data?['total']);
    final empty = total == null && groups.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('第二课堂分'),
        actions: [
          IconButton(
            tooltip: '达标线设置',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openTargetSettings,
          ),
        ],
      ),
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
                    if (data != null && _policy.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('本年级达标线尚未配置，仅显示实际分数',
                            style: TextStyle(fontSize: 11.5, color: SemColors.textMuted)),
                      ),
                    if (data != null && total != null) ...[
                      const SizedBox(height: 14),
                      _stats(data, total, _policy),
                      const SizedBox(height: 16),
                    ],
                    for (var gi = 0; gi < groups.length; gi++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _groupTile(groups[gi], gi, groups.length, _policy),
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

  // ── 总得分 / 实践学分 两个大数字（cs-stats） ──
  Widget _stats(Map<String, dynamic> data, num total, ScoreTargetPolicy policy) {
    final credit = asNum(data['credit']);
    final target = policy.total;
    final reached = target != null && credit != null && credit >= target;
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
                      color: target == null || credit == null
                          ? SemColors.textPrimary
                          : (reached ? SemColors.success : SemColors.danger)),
                ),
                if (target != null) ...[
                  const SizedBox(width: 4),
                  Text('/ ${_fmtNum(target)}',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700,
                          color: SemColors.textSecondary)),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ── 分组（cs-group）：美育/健康教育单行平铺，其余可展开 ──
  Widget _groupTile(Map<String, dynamic> group, int gi, int groupCount, ScoreTargetPolicy policy) {
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

    return _ScoreGroupTile(
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
      targetVal != null
          ? '${_fmtNum(actual)} / ${_fmtNum(targetVal)}'
          : _fmtNum(actual),
      color: color,
      soft: targetVal == null
          ? SemColors.accentSoft
          : (reached ? SemColors.successSoft : SemColors.dangerSoft),
    );
  }
}

// ── 可展开分组（受控手风琴，复刻 cs-group-summary / cs-group-body）──

class _ScoreGroupTile extends StatefulWidget {
  const _ScoreGroupTile({
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
                      targetVal != null
                          ? '${_fmtNum(actual)} / ${_fmtNum(targetVal)}'
                          : _fmtNum(actual),
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
    final subTarget = widget.policy.subFor(name);
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
