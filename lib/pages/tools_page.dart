import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_state.dart';
import 'activities_page.dart';
import 'electricity_page.dart';
import 'exams_page.dart';
import 'grades_page.dart';
import 'score_page.dart';
import '../widgets/common.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  @override
  void initState() {
    super.initState();
    _prefetch();
  }

  /// 预取二课分数与电费，供卡面速览（电费走公网直连，二课分数走隧道串行队列）。
  Future<void> _prefetch() async {
    if (!AppState.I.loggedIn) return;
    try {
      final r = await ApiClient.I.score();
      ToolCache.score = r['data'] as Map<String, dynamic>?;
      AppState.I.studentInfo = ToolCache.score?['student'] as Map<String, dynamic>?;
      if (mounted) setState(() {});
    } catch (_) {}
    try {
      final r = await ApiClient.I.electricityQuery();
      ToolCache.electricity = r['data'] as Map<String, dynamic>?;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  String _scoreSub() {
    final s = ToolCache.score;
    if (s == null) return '达标进度与明细';
    return '${s['credit']} / ${s['total']} 分';
  }

  String _eleSub() {
    final e = ToolCache.electricity;
    if (e == null) return '余额查询与充值';
    return '余额 ¥${e['balance']}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tools = [
      _Tool(Icons.fact_check_rounded, Colors.blue, '成绩单', '历年成绩与 GPA', () => const GradesPage()),
      _Tool(Icons.event_note_rounded, Colors.orange, '考试安排', '期中 / 期末安排', () => const ExamsPage()),
      _Tool(Icons.military_tech_rounded, Colors.green, '二课分数', _scoreSub(), () => const ScorePage()),
      _Tool(Icons.local_activity_rounded, Colors.purple, '二课活动', '报名状态一览', () => const ActivitiesPage()),
      _Tool(Icons.bolt_rounded, Colors.amber.shade700, '宿舍电费', _eleSub(), () => const ElectricityPage()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('工具')),
      body: LoginGate(
        child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        children: [
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.42,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final t in tools)
                AppCard(
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => t.open()))
                      .then((_) => setState(() {})),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: t.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(t.icon, color: t.color, size: 24),
                      ),
                      const Spacer(),
                      Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        t.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        ),
      ),
    );
  }
}

class _Tool {
  const _Tool(this.icon, this.color, this.title, this.subtitle, this.open);
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget Function() open;
}
