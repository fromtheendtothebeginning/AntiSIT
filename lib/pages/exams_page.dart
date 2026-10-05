import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../widgets/common.dart';

class ExamsPage extends StatefulWidget {
  const ExamsPage({super.key});

  @override
  State<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends State<ExamsPage> {
  bool _loading = true;
  String? _err;
  List<Map<String, dynamic>> _exams = [];

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
      final (xnm, xqm) = AppState.inferSemester(DateTime.now());
      final r = await ApiClient.I.exams(xnm, xqm);
      _exams = ((r['exams'] as List?) ?? const []).cast<Map<String, dynamic>>();
    } catch (e) {
      _err = e is ApiError ? e.message : e.toString();
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
        loading: _loading,
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
