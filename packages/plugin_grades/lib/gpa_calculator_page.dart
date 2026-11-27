import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'gpa_math.dart';

/// 绩点计算器：勾选部分课程，按「类别 tag / 学期」批量选，实时给出加权绩点。
///
/// 与「成绩查询」页共用同一份成绩数据（成绩页把当前列表传进来），这里只算不拉。
class GpaCalculatorPage extends StatefulWidget {
  const GpaCalculatorPage({super.key, required this.grades});

  /// 候选课程（成绩页当前筛选出来的那一批）。
  final List<Map<String, dynamic>> grades;

  @override
  State<GpaCalculatorPage> createState() => _GpaCalculatorPageState();
}

class _GpaCalculatorPageState extends State<GpaCalculatorPage> {
  /// 选中的课（按 [courseKeyOf] 记，跨学期同名课不会串）。
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    // 打开时默认全选：用户最常见的动作是「去掉几门再算」，从全选往下减更快。
    for (final g in widget.grades) {
      _selected.add(courseKeyOf(g));
    }
  }

  List<Map<String, dynamic>> get _chosen =>
      widget.grades.where((g) => _selected.contains(courseKeyOf(g))).toList();

  void _selectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll(widget.grades.map(courseKeyOf));
    });
  }

  void _selectAllExceptGeneral() {
    setState(() {
      _selected
        ..clear()
        ..addAll(
          widget.grades.where((g) => !isGeneralCourse(g)).map(courseKeyOf),
        );
    });
  }

  void _clearAll() => setState(_selected.clear);

  /// 按某个类别 tag 批量加 / 减：已全选就去掉这一类，否则补上这一类。
  void _toggleTag(String tag) {
    final keys = widget.grades
        .where((g) => courseTagOf(g) == tag)
        .map(courseKeyOf)
        .toList();
    if (keys.isEmpty) return;
    final allIn = keys.every(_selected.contains);
    setState(() {
      if (allIn) {
        _selected.removeAll(keys);
      } else {
        _selected.addAll(keys);
      }
    });
  }

  /// 按学期批量加 / 减（同一套「已全选就去掉」逻辑）。
  void _toggleTerm(String term) {
    final keys = widget.grades
        .where((g) => termLabelOf(g) == term)
        .map(courseKeyOf)
        .toList();
    if (keys.isEmpty) return;
    final allIn = keys.every(_selected.contains);
    setState(() {
      if (allIn) {
        _selected.removeAll(keys);
      } else {
        _selected.addAll(keys);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = glassTopInset(context);
    final tags = courseTagOptions(widget.grades);
    final terms = termOptions(widget.grades);
    final result = computeWeightedGpa(_chosen);
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) => Scaffold(
        extendBodyBehindAppBar: glassTopBarEnabled,
        appBar: glassAppBar(context, title: const Text('绩点计算器')),
        body: GlassFadedBody(
          barHeight: topInset,
          child: ListView(
            padding: EdgeInsets.fromLTRB(12, 8 + topInset, 12, 24),
            children: [
              // 结果卡：加权绩点 + 学分合计 + 参与门数
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BigStat(
                          label: '加权绩点',
                          value: result.gpa == null
                              ? '—'
                              : result.gpa!.toStringAsFixed(2),
                          color: SemColors.accent,
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '已选 ${result.count} 门 · ${_fmt(result.credit)} 学分',
                              style: TextStyle(
                                fontSize: 12,
                                color: SemColors.textSecondary,
                              ),
                            ),
                            if (result.skipped > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${result.skipped} 门缺学分 / 绩点未参与计算',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: SemColors.warning,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '加权绩点 = Σ(绩点 × 学分) / Σ学分，只算勾选的课程',
                      style: TextStyle(
                        fontSize: 11,
                        color: SemColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // 批量选择：全选 / 除通识课全选 / 清空
              AppCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('批量选择'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _action('全选', _selectAll),
                        _action('除通识课全选', _selectAllExceptGeneral),
                        _action('清空', _clearAll),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('按类别（可多选）'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in tags) _toggleChip(t, _toggleTag),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (terms.isNotEmpty) ...[
                const SizedBox(height: 10),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('按学期（可多选）'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in terms) _toggleChip(t, _toggleTerm),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _sectionTitle('课程（${widget.grades.length} 门，勾选即参与计算）'),
              const SizedBox(height: 6),
              for (final g in widget.grades) _courseTile(g, result),
              const PageNotes(
                lines: [
                  '勾选状态只在本次打开有效：返回成绩页再进来会重新全选。',
                  '缺学分或缺绩点的课程（成绩为「P」「合格」这类）不参与加权，已单独标出。',
                  '类别与学期标签来自学校成绩单字段；学校没给的课不归入任何 tag。',
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(num v) {
    final r = (v * 1000).round() / 1000;
    return r == r.roundToDouble() ? r.round().toString() : r.toString();
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: SemColors.textSecondary,
    ),
  );

  Widget _action(String label, VoidCallback onTap) => FilledButton.tonal(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
    child: Text(label),
  );

  /// 类别 / 学期胶囊：这一类已全部选中就高亮，表示「再点一下取消这一类」。
  Widget _toggleChip(String label, void Function(String) onTap) {
    final keys = widget.grades
        .where((g) => label == courseTagOf(g) || label == termLabelOf(g))
        .map(courseKeyOf)
        .toList();
    final allIn = keys.isNotEmpty && keys.every(_selected.contains);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => onTap(label),
      child: Capsule(
        label,
        color: allIn ? SemColors.accent : SemColors.textMuted,
      ),
    );
  }

  Widget _courseTile(Map<String, dynamic> g, GpaResult result) {
    final key = courseKeyOf(g);
    final on = _selected.contains(key);
    final credit = asNum(g['xf']);
    final point = asNum(g['jd']);
    final countable = credit != null && point != null;
    final tag = courseTagOf(g);
    final term = termLabelOf(g);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AppCard(
        radius: 10,
        padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
        onTap: () => setState(() {
          if (on) {
            _selected.remove(key);
          } else {
            _selected.add(key);
          }
        }),
        child: Row(
          children: [
            Checkbox(
              value: on,
              onChanged: (_) => setState(() {
                if (on) {
                  _selected.remove(key);
                } else {
                  _selected.add(key);
                }
              }),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${g['kcmc']}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: countable || !on
                          ? SemColors.textPrimary
                          : SemColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (tag.isNotEmpty) tag,
                      term,
                      if (credit != null) '${_fmt(credit)} 学分',
                      if (point != null)
                        '绩点 ${point.toStringAsFixed(1)}'
                      else
                        '无绩点',
                    ].join(' · '),
                    style: TextStyle(fontSize: 11, color: SemColors.textMuted),
                  ),
                ],
              ),
            ),
            Text(
              '${g['cj'] ?? ''}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: countable ? SemColors.accent : SemColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
