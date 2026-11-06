import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 学业情况（教务「学生学业情况查询」，N105515）：
/// 整体统计（平均学分绩点 / 计划内外课程通过数）+ 按课程类别分组的
/// 学分要求（要求 / 获得 / 未获得）与该类别下的课程明细。
///
/// 缓存与刷新行为与成绩页一致：进入先读 [ToolPageCache] 立即展示，
/// 再按 [AppState.autoRefreshTools] 决定是否后台拉新；刷新失败时保留旧数据，
/// 只在顶部 [ToolRefreshBar] 提示，整页失败（且无缓存）才进错误态 + [showErr]。
class AcademicPage extends StatefulWidget {
  const AcademicPage({super.key});

  @override
  State<AcademicPage> createState() => _AcademicPageState();
}

class _AcademicPageState extends State<AcademicPage> {
  bool _loading = true;
  String? _err;
  Map<String, dynamic>? _data;

  /// 当前展示的是本机缓存 / 本次刷新失败（顶部刷新条用）。
  bool _fromCache = false;
  bool _refreshFailed = false;

  static const _cacheKey = 'academic';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// 先读本机缓存立即展示，再按「工具页自动刷新」设置决定是否后台拉新。
  Future<void> _restore() async {
    final cached = await ToolPageCache.read(_cacheKey);
    final data = _objOf(cached?['data']);
    if (!mounted) return;
    if (data != null) {
      setState(() {
        _data = data;
        _loading = false;
        _fromCache = true;
      });
    }
    if (!AppState.I.autoRefreshTools && data != null) return;
    await _load();
  }

  Future<void> _load() async {
    if (_loading && _data != null) return;
    setState(() {
      _loading = true;
      _refreshFailed = false;
      if (_data == null) _err = null;
    });
    try {
      final r = await ApiClient.I.academicStatus();
      final data = _objOf(r['data']);
      // 解析层已把学校 alert-danger 抬成 ApiError；这里再兜一层：
      // 个别实现会把错误塞在 data.error 里，同时返回空统计 + 空类别。
      final msg = _strOf(data?['error']);
      if (msg.isNotEmpty) throw ApiError('学业情况查询失败：$msg');
      _data = data ?? const <String, dynamic>{};
      _fromCache = false;
      await ToolPageCache.write(_cacheKey, {'data': _data});
    } catch (e) {
      // 有缓存时保留旧数据、只在顶部提示失败，不弹窗打断。
      if (_data == null) {
        _err = e is ApiError ? e.message : e.toString();
        if (mounted) showErr(context, e, title: '学业情况加载失败');
      } else {
        _refreshFailed = true;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final stats = _objOf(data?['statistics']);
    final planed = _objOf(stats?['planed']);
    final unplaned = _objOf(stats?['unplaned']);
    final categories = _listOf(data?['categories']);
    final byId = <String, Map<String, dynamic>>{
      for (final c in categories) _strOf(c['id']): c,
    };
    List<Map<String, dynamic>> childrenOf(String parent) => [
          for (final c in categories)
            if (_strOf(c['parent']) == parent) c,
        ];
    final roots = [
      for (final c in categories)
        if (_strOf(c['parent']).isEmpty || !byId.containsKey(_strOf(c['parent']))) c,
    ];
    final gpa = asNum(stats?['gpa']);
    final sid = _strOf(data?['sid']);
    final hasContent = _hasContent(data);

    return Scaffold(
      appBar: AppBar(title: const Text('学业情况')),
      body: PageStateView(
        loading: _loading && data == null,
        error: _err,
        empty: !_loading && _err == null && !hasContent,
        emptyText: '暂无学业情况数据：教务系统可能未返回统计与课程类别',
        onRetry: _load,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            children: [
              ToolRefreshBar(
                refreshing: _loading,
                fromCache: _fromCache,
                failed: _refreshFailed,
                onRefresh: _load,
              ),
              _gpaCard(gpa, sid, planed),
              if (planed != null || unplaned != null) _statsCard(planed, unplaned),
              if (categories.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                  child: Row(
                    children: [
                      Text(
                        '修读课程类别',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: SemColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '共 ${categories.length} 类',
                        style: TextStyle(fontSize: 11.5, color: SemColors.textMuted),
                      ),
                    ],
                  ),
                ),
                for (final cat in roots) _categoryNode(cat, childrenOf(_strOf(cat['id'])), 0),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                child: Text(
                  '数据来自教务系统「学生学业情况查询」，仅含培养方案内的修读要求，供学业规划参考。',
                  style: TextStyle(fontSize: 11, height: 1.6, color: SemColors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 顶部：平均学分绩点大数字 + 学号 / 计划课程数 ──
  Widget _gpaCard(num? gpa, String sid, Map<String, dynamic>? planed) {
    final total = asInt(planed?['total']);
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BigStat(
            label: '平均学分绩点',
            value: gpa == null ? '—' : gpa.toStringAsFixed(2),
            color: SemColors.accent,
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (sid.isNotEmpty)
                Text(
                  '学号 $sid',
                  style: TextStyle(fontSize: 12, color: SemColors.textSecondary),
                ),
              if (total != null) ...[
                const SizedBox(height: 4),
                Text(
                  '计划总课程 $total 门',
                  style: TextStyle(fontSize: 12, color: SemColors.textMuted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── 整体统计：计划内（总/通过/未通过/未修/在读）+ 计划外（通过/未通过） ──
  Widget _statsCard(Map<String, dynamic>? planed, Map<String, dynamic>? unplaned) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (planed != null) ...[
            _sectionLine('计划内课程'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _stat('总课程', planed['total']),
                _stat('通过', planed['passed'], color: SemColors.success),
                _stat('未通过', planed['failed'], color: SemColors.danger),
                _stat('未修', planed['missed']),
                _stat('在读', planed['in']),
              ],
            ),
          ],
          if (planed != null && unplaned != null) const SizedBox(height: 16),
          if (unplaned != null) ...[
            _sectionLine('计划外课程'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _stat('通过', unplaned['passed'], color: SemColors.success),
                _stat('未通过', unplaned['failed'], color: SemColors.danger),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 统计小格：值可能缺失（学校页面只回部分字段），缺失显示占位符而不是编造 0。
  Widget _stat(String label, Object? value, {Color? color}) {
    final n = asInt(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
        const SizedBox(height: 2),
        Text(
          n == null ? '—' : '$n',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.1,
            color: n == null ? SemColors.textMuted : (color ?? SemColors.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _sectionLine(String text) => Row(
        children: [
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              color: SemColors.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: SemColors.textPrimary,
            ),
          ),
        ],
      );

  // ── 课程类别（可递归的手风琴）：标题行给学分要求，展开是子类别与课程明细 ──
  Widget _categoryNode(
    Map<String, dynamic> cat,
    List<Map<String, dynamic>> children,
    int level,
  ) {
    final name = _strOf(cat['name']);
    final required = asNum(cat['required']);
    final earned = asNum(cat['earned']);
    final missed = asNum(cat['missed']);
    final courses = _listOf(cat['courses']);
    final coursesError = _strOf(cat['coursesError']);
    final isLeaf = children.isEmpty;
    final credits = [
      if (required != null) '要求 ${_fmtNum(required)}',
      if (earned != null) '获得 ${_fmtNum(earned)}',
      if (missed != null) '未获得 ${_fmtNum(missed)}',
    ];
    // 只有叶子节点能拉到课程明细（父节点的明细接口在真实教务里本来就只有空数组）。
    final childrenWidgets = [
      for (final child in children)
        _categoryNode(child, _childrenOfCategory(_strOf(child['id'])), level + 1),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: SemColors.stripe,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SemColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // 只有一个叶子类别时默认展开：省一次点击，多类别时保持收起的可扫读性。
        initiallyExpanded: isLeaf && courses.length == 1,
        tilePadding: EdgeInsets.only(left: 14.0 + level * 12, right: 14),
        childrenPadding: EdgeInsets.only(left: 14.0 + level * 12, right: 14, bottom: 10),
        iconColor: SemColors.textMuted,
        collapsedIconColor: SemColors.textMuted,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          name.isEmpty ? '未命名类别' : name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: SemColors.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final t in credits) _chip(t),
              if (!isLeaf) _chip('${children.length} 个子类'),
              // 明细拉取失败时课程数未知，不显示；正常拉到就显示（含 0 门）。
              if (isLeaf && coursesError.isEmpty) _chip('${courses.length} 门'),
            ],
          ),
        ),
        children: [
          ...childrenWidgets,
          if (isLeaf) ...[
            if (coursesError.isNotEmpty)
              _hintRow('课程明细加载失败（$coursesError）')
            else if (courses.isEmpty)
              _hintRow('暂无课程明细')
            else
              for (var i = 0; i < courses.length; i++)
                _courseRow(courses[i], i == courses.length - 1),
          ],
        ],
      ),
    );
  }

  /// 从完整类别表里找某个 id 的子类别（递归渲染时需要跨层级找子节点）。
  List<Map<String, dynamic>> _childrenOfCategory(String id) => [
        for (final c in _allCategories)
          if (_strOf(c['parent']) == id) c,
      ];

  /// 完整类别表（递归渲染时需要跨层级找子节点）。
  List<Map<String, dynamic>> get _allCategories => _listOf(_data?['categories']);

  /// 课程行：课程名 + 标签（性质 / 建议学期 / 修读状态 / 课程号），右侧成绩与学分绩点。
  Widget _courseRow(Map<String, dynamic> c, bool last) {
    final name = _strOf(c['name']);
    final code = _strOf(c['code']);
    final credit = asNum(c['credit']);
    final scoreText = _strOf(c['score']);
    final scoreNum = asNum(c['score']);
    final point = asNum(c['point']);
    final nature = _strOf(c['nature']);
    final term = _strOf(c['term']);
    final statusText = _strOf(c['statusText']);
    final tags = [
      if (nature.isNotEmpty) nature,
      if (term.isNotEmpty) term,
      if (statusText.isNotEmpty) statusText,
    ];
    final meta = [
      if (credit != null) '学分 ${_fmtNum(credit)}',
      if (point != null) '绩点 ${_fmtNum(point)}',
    ].join(' · ');
    // 成绩能解析成数字时按及格线着色；「优秀 / 合格」这类文本保持中性色。
    final scoreColor = scoreNum == null
        ? SemColors.textPrimary
        : (scoreNum < 60 ? SemColors.danger : SemColors.success);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: SemColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? '未命名课程' : name,
                  style: TextStyle(fontSize: 13, color: SemColors.textPrimary),
                ),
                if (code.isNotEmpty || tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (code.isNotEmpty) _chip(code),
                      for (final t in tags) _chip(t),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                scoreText.isEmpty ? '—' : scoreText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: scoreColor,
                ),
              ),
              if (meta.isNotEmpty)
                Text(
                  meta,
                  style: TextStyle(fontSize: 11, color: SemColors.textMuted),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hintRow(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: SemColors.textMuted),
        ),
      );

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: SemColors.neutralSoft,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, color: SemColors.textMuted)),
      );

  /// 有没有可展示的内容：只有学号、统计与类别全空时按「无数据」处理。
  bool _hasContent(Map<String, dynamic>? data) {
    if (data == null) return false;
    final stats = _objOf(data['statistics']);
    return asNum(stats?['gpa']) != null ||
        _objOf(stats?['planed']) != null ||
        _objOf(stats?['unplaned']) != null ||
        _listOf(data['categories']).isNotEmpty;
  }
}

/// 宽容取子对象：字段可能缺失 / 为 null / 不是 Map（服务器换实现时）。
Map<String, dynamic>? _objOf(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

/// 宽容取对象列表：非 List 或元素不是 Map 时跳过，不让单个脏元素炸整页。
List<Map<String, dynamic>> _listOf(Object? v) => v is List
    ? [
        for (final e in v)
          if (e is Map) e.cast<String, dynamic>(),
      ]
    : const [];

String _strOf(Object? v) => '${v ?? ''}'.trim();

/// 学分数值：整数不带小数点（28.0 → 28），小数原样保留。
String _fmtNum(num v) => v == v.roundToDouble() ? v.round().toString() : v.toString();
