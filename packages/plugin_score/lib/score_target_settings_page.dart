import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 三级页面：调整本机二课达标线。
///
/// 只改 App 的「达标对比线」，不改变学校返回的分数；修改按入学年级保存在本机，
/// 优先于远端配置。留空表示该项不比较。
class ScoreTargetSettingsPage extends StatefulWidget {
  const ScoreTargetSettingsPage({super.key, this.cohort});

  /// 当前年级（入学年）；不传时依次用直连凭据 / 学籍缓存里填的年级。
  final String? cohort;

  @override
  State<ScoreTargetSettingsPage> createState() => _ScoreTargetSettingsPageState();
}

class _ScoreTargetSettingsPageState extends State<ScoreTargetSettingsPage> {
  bool _loading = true;
  String? _err;
  ScoreTargetPolicy _policy = const ScoreTargetPolicy();
  String _cohort = '';
  bool _hasLocal = false;

  TextEditingController _total = TextEditingController();
  final List<TextEditingController> _groups = [];
  final List<TextEditingController> _subs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _total.dispose();
    for (final c in _groups) {
      c.dispose();
    }
    for (final c in _subs) {
      c.dispose();
    }
    super.dispose();
  }

  String get _cohortFromContext {
    if (AppState.I.direct) {
      final creds = AppState.I.creds.grade.trim();
      if (creds.isNotEmpty) return creds;
    }
    final passed = (widget.cohort ?? '').trim();
    if (passed.isNotEmpty) return passed;
    final info = AppState.I.studentInfo;
    if (info != null) return '${info['nj'] ?? ''}'.trim();
    return '';
  }

  void _resetControllers() {
    _total.dispose();
    for (final c in _groups) {
      c.dispose();
    }
    for (final c in _subs) {
      c.dispose();
    }
    _groups.clear();
    _subs.clear();
    _total = TextEditingController();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final targets = await ScoreTargets.load();
      final cohort = _cohortFromContext;
      final policy = targets.forCohort(cohort);
      _resetControllers();
      _cohort = cohort;
      _policy = policy;
      _hasLocal = targets.localOverrideFor(cohort) != null;
      _total.text = _fmt(policy.total);
      _groups.addAll([
        for (final g in policy.groups) TextEditingController(text: _fmt(g.target)),
      ]);
      _subs.addAll([
        for (final s in policy.subs) TextEditingController(text: _fmt(s.target)),
      ]);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = '$e';
          _loading = false;
        });
      }
    }
  }

  double? _parse(TextEditingController c) {
    final s = c.text.trim();
    if (s.isEmpty) return null;
    final v = double.tryParse(s);
    if (v == null || v < 0) throw const FormatException('请输入不小于 0 的数字，留空表示不比较');
    return v;
  }

  Future<void> _save() async {
    setState(() => _err = null);
    try {
      final policy = ScoreTargetPolicy(
        label: _policy.label,
        total: _parse(_total),
        groups: [
          for (var i = 0; i < _policy.groups.length; i++)
            ScoreGroupTarget(
              keywords: _policy.groups[i].keywords,
              target: _parse(_groups[i]),
              noExpand: _policy.groups[i].noExpand,
            ),
        ],
        subs: [
          for (var i = 0; i < _policy.subs.length; i++)
            ScoreSubTarget(keywords: _policy.subs[i].keywords, target: _parse(_subs[i])),
        ],
      );
      await ScoreTargets.saveLocalOverride(_cohort.isEmpty ? null : _cohort, policy);
      if (!mounted) return;
      setState(() => _hasLocal = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已保存本机达标线'), behavior: SnackBarBehavior.floating));
    } on FormatException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _reset() async {
    await ScoreTargets.saveLocalOverride(_cohort.isEmpty ? null : _cohort, null);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已恢复默认达标线'), behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _openConnect() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ConnectPage()));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('第二课堂达标线')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_cohort.isEmpty ? '未填写年级' : '当前年级 $_cohort',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                        _cohort.isEmpty
                            ? '未填年级时，这里的调整作为默认自定义规则'
                            : (_hasLocal ? '当前使用本机自定义达标线' : '当前使用默认 / 远端达标线'),
                        style: TextStyle(fontSize: 12, color: SemColors.textSecondary, height: 1.6),
                      ),
                      if (_cohort.isEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _openConnect,
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('去直连设置填写年级'),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('实践学分总目标',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('留空表示不比较总分',
                          style: TextStyle(fontSize: 11.5, color: SemColors.textMuted)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _total,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          suffixText: '分',
                          hintText: '如 8',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_policy.groups.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('一级板块目标',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('留空表示该板块不比较',
                            style: TextStyle(fontSize: 11.5, color: SemColors.textMuted)),
                        const SizedBox(height: 6),
                        for (var i = 0; i < _policy.groups.length; i++)
                          _targetRow(
                            label: _policy.groups[i].keywords.join(' / '),
                            controller: _groups[i],
                          ),
                      ],
                    ),
                  ),
                ],
                if (_policy.subs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('二级条目目标',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('留空表示该条目只显示实际值',
                            style: TextStyle(fontSize: 11.5, color: SemColors.textMuted)),
                        const SizedBox(height: 6),
                        for (var i = 0; i < _policy.subs.length; i++)
                          _targetRow(
                            label: _policy.subs[i].keywords.join(' / '),
                            controller: _subs[i],
                          ),
                      ],
                    ),
                  ),
                ],
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_err!,
                        style: TextStyle(fontSize: 12, color: SemColors.danger, height: 1.6)),
                  ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _hasLocal ? _reset : null,
                        child: const Text('恢复默认'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(onPressed: _save, child: const Text('保存')),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '只调整 App 的达标对比线，不改变学校返回的分数；修改只保存在本机。',
                  style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6),
                ),
              ],
            ),
    );
  }

  Widget _targetRow({required String label, required TextEditingController controller}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: SemColors.textSecondary)),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.end,
              decoration: const InputDecoration(
                suffixText: '分',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(num? v) =>
    v == null ? '' : (v == v.roundToDouble() ? v.round().toString() : v.toString());
