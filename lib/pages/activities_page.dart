import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../widgets/common.dart';

enum _ActState { signing, upcoming, ended }

/// 报名状态：按本机时间对 bm_start / bm_end 判断。
_ActState _stateOf(Map<String, dynamic> a) {
  DateTime? p(dynamic s) {
    final str = s?.toString() ?? '';
    return str.isEmpty ? null : DateTime.tryParse(str.replaceAll(' ', 'T'));
  }

  final now = DateTime.now();
  final bs = p(a['bm_start']);
  final be = p(a['bm_end']);
  if (bs != null && now.isBefore(bs)) return _ActState.upcoming;
  if (be != null && now.isAfter(be)) return _ActState.ended;
  return _ActState.signing;
}

String _stateText(_ActState s) => switch (s) {
      _ActState.signing => '报名中',
      _ActState.upcoming => '即将报名',
      _ActState.ended => '报名已结束',
    };

Color _stateColor(_ActState s) => switch (s) {
      _ActState.signing => SemColors.success,
      _ActState.upcoming => SemColors.accent,
      _ActState.ended => SemColors.textMuted,
    };

class ActivitiesPage extends StatefulWidget {
  const ActivitiesPage({super.key});

  @override
  State<ActivitiesPage> createState() => _ActivitiesPageState();
}

class _ActivitiesPageState extends State<ActivitiesPage> {
  bool _loading = true;
  String? _err;
  List<Map<String, dynamic>> _list = [];
  String _query = '';
  int _filter = 0; // 0全部 1报名中 2即将报名 3已结束

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
      final r = await ApiClient.I.activities();
      _list = (((r['data'] as Map?)?['activities'] as List?) ?? const []).cast<Map<String, dynamic>>();
    } catch (e) {
      _err = e is ApiError ? e.message : e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _list.where((a) {
      final st = _stateOf(a);
      if (_filter == 1 && st != _ActState.signing) return false;
      if (_filter == 2 && st != _ActState.upcoming) return false;
      if (_filter == 3 && st != _ActState.ended) return false;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        final hay = '${a['name']} ${a['host']} ${a['dlmc']} ${a['lbmc']}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final rank = switch (_stateOf(a)) {
          _ActState.signing => 0,
          _ActState.upcoming => 1,
          _ActState.ended => 2,
        };
        final rankB = switch (_stateOf(b)) {
          _ActState.signing => 0,
          _ActState.upcoming => 1,
          _ActState.ended => 2,
        };
        if (rank != rankB) return rank - rankB;
        if (rank == 0) {
          // 报名中按截止时间升序
          return ('${a['bm_end']}'.compareTo('${b['bm_end']}'));
        }
        return '${b['start']}'.compareTo('${a['start']}');
      });
    return list;
  }

  int _countOf(int filter) {
    var n = 0;
    for (final a in _list) {
      final st = switch (_stateOf(a)) {
        _ActState.signing => 1,
        _ActState.upcoming => 2,
        _ActState.ended => 3,
      };
      if (st == filter) n++;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('第二课堂活动')),
      body: PageStateView(
        loading: _loading,
        error: _err,
        empty: !_loading && _err == null && _list.isEmpty,
        emptyText: '暂无活动',
        onRetry: _load,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
            children: [
              TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: const InputDecoration(
                  hintText: '搜索活动名称 / 主办 / 类别…',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final (i, label) in const [(0, '全部'), (1, '报名中'), (2, '即将报名'), (3, '已结束')])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _FilterChip(
                          label: i == 0 ? label : '$label (${_countOf(i)})',
                          selected: _filter == i,
                          onTap: () => setState(() => _filter = i),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('共 ${list.length} 个活动',
                    style: const TextStyle(fontSize: 12, color: SemColors.textMuted)),
              ),
              const SizedBox(height: 6),
              for (final a in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    radius: 10,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ActivityDetailPage(id: '${a['id']}', activity: a))),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Capsule(_stateText(_stateOf(a)), color: _stateColor(_stateOf(a))),
                            if (a['backfill'] as bool? ?? false)
                              const Capsule('事后补录', color: SemColors.info),
                            Capsule('${a['campus']}'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('${a['name']}',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600,
                                color: SemColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text('${a['dlmc']} · ${a['lbmc']}',
                            style: const TextStyle(fontSize: 12, color: SemColors.textSecondary)),
                        const SizedBox(height: 6),
                        _row('主办：${a['host']}  ·  名额：${a['quota'] ?? '—'}'),
                        const SizedBox(height: 2),
                        _row('活动时间：${_short(a['start'])} ~ ${_short(a['end'])}'),
                        _row('报名窗口：${_short(a['bm_start'])} ~ ${_short(a['bm_end'])}'),
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

  Widget _row(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: const TextStyle(fontSize: 12, color: SemColors.textMuted),
            overflow: TextOverflow.ellipsis,
            maxLines: 1),
      );

  String _short(Object? s) {
    final str = '$s';
    return str.length >= 16 ? str.substring(5, 16) : str;
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? SemColors.accentSoft : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? SemColors.accent : SemColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? SemColors.accent : SemColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class ActivityDetailPage extends StatefulWidget {
  const ActivityDetailPage({super.key, required this.id, this.activity});

  final String id;

  /// 列表项数据：详情接口只返回 id/hdms/quota/signup，
  /// 名称、时间、校区等元信息从这里取。
  final Map<String, dynamic>? activity;

  @override
  State<ActivityDetailPage> createState() => _ActivityDetailPageState();
}

class _ActivityDetailPageState extends State<ActivityDetailPage> {
  bool _loading = true;
  String? _err;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _data = widget.activity == null ? null : Map<String, dynamic>.from(widget.activity!);
    _load();
  }

  Future<void> _load() async {
    final hasBase = _data != null && _data!.isNotEmpty;
    setState(() {
      _loading = !hasBase;
      _err = null;
    });
    try {
      final r = await ApiClient.I.activityDetail(widget.id);
      // 详情接口结果（完整说明/名额/报名方式）覆盖列表数据；其余元信息保留列表项内容。
      _data = {...?_data, ...?r['data'] as Map<String, dynamic>?};
    } catch (e) {
      // 已有列表项数据时不必因详情拉取失败而整页报错。
      if (_data == null || _data!.isEmpty) {
        _err = e is ApiError ? e.message : e.toString();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已复制$label：$value'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final signup = (_data?['signup'] as Map<String, dynamic>?) ?? {};
    final a = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('活动详情')),
      body: PageStateView(
        loading: _loading,
        error: _err,
        onRetry: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (a != null)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Capsule(_stateText(_stateOf(a)), color: _stateColor(_stateOf(a))),
                        if (a['backfill'] as bool? ?? false) const Capsule('事后补录', color: SemColors.info),
                        Capsule('${a['dlmc']}', color: SemColors.accent),
                        Capsule('${a['lbmc']}', color: SemColors.accent),
                      ],
                    ),
                  if (a != null) const SizedBox(height: 10),
                  Text('${a?['name'] ?? ''}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: SemColors.textPrimary)),
                  const Divider(height: 24),
                  _kv('活动时间', '${a?['start'] ?? '-'} ~ ${a?['end'] ?? '-'}'),
                  _kv('报名时间', '${a?['bm_start'] ?? '-'} ~ ${a?['bm_end'] ?? '-'}'),
                  _kv('名额', '${a?['quota'] ?? '-'}'),
                  _kv('校区', '${a?['campus'] ?? '-'}'),
                  _kv('主办方', '${a?['host'] ?? '-'}'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (signup.isNotEmpty)
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('报名方式', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (final qq in ((signup['qq'] as List?) ?? const []))
                      _contact('QQ群：', '$qq'),
                    for (final ph in ((signup['phone'] as List?) ?? const []))
                      _contact('电话：', '$ph'),
                    for (final tips in ((signup['tips'] as List?) ?? const []))
                      _bullet('$tips'),
                    for (final line in ((signup['contact_lines'] as List?) ?? const []))
                      _bullet('$line'),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('活动说明', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SelectableText(
                    '${_data?['hdms'] ?? '暂无活动说明'}',
                    style: const TextStyle(fontSize: 13, height: 1.7, color: SemColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 68,
              child: Text(k, style: const TextStyle(fontSize: 13, color: SemColors.textMuted)),
            ),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: Icon(Icons.circle, size: 4, color: SemColors.textMuted),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 12, color: SemColors.textSecondary))),
          ],
        ),
      );

  Widget _contact(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: SemColors.textMuted)),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => _copy(label, value),
              icon: const Icon(Icons.copy_rounded, size: 16, color: SemColors.textMuted),
            ),
          ],
        ),
      );
}
