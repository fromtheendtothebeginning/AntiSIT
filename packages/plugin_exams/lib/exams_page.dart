import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

class ExamsPage extends StatefulWidget {
  const ExamsPage({super.key});

  @override
  State<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends ToolPageState<ExamsPage> {
  List<Map<String, dynamic>> _exams = [];

  /// 缓存按学期隔离：换学期后不会把上学期的安排当成本学期。
  static String _cacheKey(String xnm, String xqm) => 'exams:$xnm:$xqm';

  @override
  String get cacheKey {
    final (xnm, xqm) = AppState.inferSemester(DateTime.now());
    return _cacheKey(xnm, xqm);
  }

  @override
  String get errorTitle => '考试安排加载失败';

  @override
  bool get hasData => _exams.isNotEmpty;

  @override
  bool applyCache(Map<String, dynamic>? cached) {
    final exams = ((cached?['exams'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (exams.isEmpty) return false;
    _exams = exams;
    return true;
  }

  @override
  Future<bool> fetchData() async {
    final (xnm, xqm) = AppState.inferSemester(DateTime.now());
    final r = await ApiClient.I.exams(xnm, xqm);
    _exams = ((r['exams'] as List?) ?? const []).cast<Map<String, dynamic>>();
    await ToolPageCache.write(_cacheKey(xnm, xqm), {'exams': _exams});
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('考试安排')),
      body: PageStateView(
        loading: loading && _exams.isEmpty,
        error: error,
        empty: !loading && error == null && _exams.isEmpty,
        emptyText: '本学期暂无考试安排',
        onRetry: refresh,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            children: [
              ToolRefreshBar(
                refreshing: loading,
                fromCache: fromCache,
                failed: refreshFailed,
                onRefresh: refresh,
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
