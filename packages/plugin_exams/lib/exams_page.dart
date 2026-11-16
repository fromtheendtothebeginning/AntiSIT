import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

class ExamsPage extends StatefulWidget {
  const ExamsPage({super.key});

  @override
  State<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends State<ExamsPage> {
  bool _loading = true;
  String? _err;
  List<Map<String, dynamic>> _exams = [];

  /// 当前展示的是本机缓存 / 本次刷新失败（顶部刷新条用）。
  bool _fromCache = false;
  bool _refreshFailed = false;

  /// 缓存按学期隔离：换学期后不会把上学期的安排当成本学期。
  static String _cacheKey(String xnm, String xqm) => 'exams:$xnm:$xqm';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// 先读本机缓存立即展示，再按「工具页自动刷新」设置决定是否后台拉新。
  Future<void> _restore() async {
    final (xnm, xqm) = AppState.inferSemester(DateTime.now());
    final cached = await ToolPageCache.read(_cacheKey(xnm, xqm));
    final exams = ((cached?['exams'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (!mounted) return;
    if (exams.isNotEmpty) {
      setState(() {
        _exams = exams;
        _loading = false;
        _fromCache = true;
      });
    }
    if (!AppState.I.autoRefreshTools && _exams.isNotEmpty) return;
    await _load();
  }

  Future<void> _load() async {
    if (_loading && _exams.isNotEmpty) return;
    setState(() {
      _loading = true;
      _refreshFailed = false;
      if (_exams.isEmpty) _err = null;
    });
    try {
      final (xnm, xqm) = AppState.inferSemester(DateTime.now());
      final r = await ApiClient.I.exams(xnm, xqm);
      _exams = ((r['exams'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _fromCache = false;
      await ToolPageCache.write(_cacheKey(xnm, xqm), {'exams': _exams});
    } catch (e) {
      // 有缓存时保留旧列表、只在顶部提示失败，不弹窗打断。
      if (_exams.isEmpty) {
        _err = e is ApiError ? e.message : e.toString();
        if (mounted) showErr(context, e, title: '考试安排加载失败');
      } else {
        _refreshFailed = true;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('考试安排')),
      body: PageStateView(
        loading: _loading && _exams.isEmpty,
        error: _err,
        empty: !_loading && _err == null && _exams.isEmpty,
        emptyText: '本学期暂无考试安排',
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
              for (final e in _exams)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('${e['name']}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('${e['ksmc']}',
                                  style: TextStyle(fontSize: 11, color: scheme.primary)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.event_rounded, size: 15, color: scheme.outline),
                            const SizedBox(width: 4),
                            Text('${e['date']}  ${e['start']} ~ ${e['end']}'),
                            const SizedBox(width: 12),
                            Icon(Icons.meeting_room_outlined, size: 15, color: scheme.outline),
                            const SizedBox(width: 4),
                            Expanded(child: Text('${e['place']}', overflow: TextOverflow.ellipsis)),
                            Text('座位 ${e['seat']}', style: TextStyle(color: scheme.outline, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('考核方式：${e['ksfs']}', style: TextStyle(fontSize: 12, color: scheme.outline)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
