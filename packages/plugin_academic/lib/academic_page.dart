import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

part 'academic_widgets.dart';

/// 学业情况：整体统计（平均学分绩点 / 计划内外通过数）+ 按类别的学分要求与课程明细。
/// 缓存与刷新同成绩页：先读 ToolPageCache 展示，再按 autoRefreshTools 决定后台拉新，失败保留旧数据。
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
      // 解析层已把学校 alert-danger 抬成 ApiError；这里再兜 data.error 里塞错误的情况。
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
    final parentIds = <String>{
      for (final c in categories)
        if (_strOf(c['parent']).isNotEmpty) _strOf(c['parent']),
    };
    bool isLeaf(Map<String, dynamic> c) => !parentIds.contains(_strOf(c['id']));
    final roots = [
      for (final c in categories)
        if (_strOf(c['parent']).isEmpty ||
            !byId.containsKey(_strOf(c['parent'])))
          c,
    ];
    // 归属到某个根节点：沿 parent 链往上走，看能否走到 root。
    bool belongsTo(Map<String, dynamic> c, Map<String, dynamic> root) {
      final rootId = _strOf(root['id']);
      var cur = _strOf(c['id']);
      final guard = <String>{};
      while (guard.add(cur)) {
        if (cur == rootId) return true;
        final p = _strOf(byId[cur]?['parent']);
        if (p.isEmpty || !byId.containsKey(p)) return false;
        cur = p;
      }
      return false;
    }

    // 面包屑：从根往下的路径（不含根自己，由分区标题表达）。
    List<String> crumbsOf(Map<String, dynamic> c) {
      final chain = <String>[];
      var parent = _strOf(c['parent']);
      final guard = <String>{};
      while (
          parent.isNotEmpty && byId.containsKey(parent) && guard.add(parent)) {
        chain.insert(0, _strOf(byId[parent]!['name']));
        parent = _strOf(byId[parent]!['parent']);
      }
      return chain.length > 1 ? chain.sublist(1) : const [];
    }

    final leavesOf = <String, List<Map<String, dynamic>>>{
      for (final r in roots)
        _strOf(r['id']): [
          for (final c in categories)
            if (isLeaf(c) && belongsTo(c, r)) c,
        ],
    };
    final gpa = asNum(stats?['gpa']);
    final sid = _strOf(data?['sid']);
    final hasContent = _hasContent(data);

    // 整页监听 AppState：顶栏样式开关改完要连 Scaffold 一起重建。
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        // 先算顶栏留白：body 里的 MediaQuery 已扣掉状态栏。
        final topInset = glassTopInset(context);
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(context, title: const Text('学业情况')),
          body: GlassFadedBody(
            barHeight: topInset,
            child: PageStateView(
            loading: _loading && data == null,
            error: _err,
            empty: !_loading && _err == null && !hasContent,
            emptyText: '暂无学业情况数据：教务系统可能未返回统计与课程类别',
            onRetry: _load,
            child: RefreshIndicator(
              // 下拉刷新圈从悬浮顶栏底边开始，不贴着屏幕最上沿。
              edgeOffset: topInset,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(12, 8 + topInset, 12, 20),
                children: [
                  ToolRefreshBar(
                    refreshing: _loading,
                    fromCache: _fromCache,
                    failed: _refreshFailed,
                    onRefresh: _load,
                  ),
                  _gpaCard(gpa, sid, planed),
                  if (planed != null || unplaned != null)
                    _statsCard(planed, unplaned),
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
                            style: TextStyle(
                              fontSize: 11.5,
                              color: SemColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 根节点做分区标题，叶子类别拍平成卡片，层级由面包屑文字表达。
                    for (final root in roots) ...[
                      _sectionHeader(root, leavesOf[_strOf(root['id'])]!.length),
                      for (final leaf in leavesOf[_strOf(root['id'])]!)
                        _leafCategoryCard(context, leaf, crumbsOf(leaf)),
                    ],
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                    child: Text(
                      '数据来自教务系统「学生学业情况查询」，仅含培养方案内的修读要求，供学业规划参考。',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.6,
                        color: SemColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        );
      },
    );
  }

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
