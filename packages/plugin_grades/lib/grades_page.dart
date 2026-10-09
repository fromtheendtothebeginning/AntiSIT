import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

class GradesPage extends StatefulWidget {
  const GradesPage({super.key});

  @override
  State<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> {
  bool _loading = true;
  String? _err;
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _terms = [];
  num _gpa = 0;
  String _xnm = ''; // '' = 全部学期
  String _xqm = '';

  /// 学期码 → 名称（接口返回 1/2 序号，旧版网站学期码 3/12/16 也兼容）。
  static String _xqName(String? s) => switch (s) {
        '1' || '3' => '第一学期',
        '2' || '12' => '第二学期',
        '16' => '短学期',
        _ => s ?? '',
      };

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
      // 选中学期时带 xnm/xqm 由服务端过滤（与网站一致）；不带则返回全部 + terms 列表
      final r = await ApiClient.I.grades(
        xnm: _xnm.isEmpty ? null : _xnm,
        xqm: _xqm.isEmpty ? null : _xqm,
      );
      final data = r['data'] as Map<String, dynamic>? ?? {};
      _all = ((data['grades'] as List?) ?? const []).cast<Map<String, dynamic>>();
      final terms = ((data['terms'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (terms.isNotEmpty) _terms = terms;
      _gpa = asNum(data['gpa']) ?? 0;
      _err = null;
    } catch (e) {
      _err = e is ApiError ? e.message : e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickTerm() async {
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('全部学期'),
              trailing: _xnm.isEmpty ? Icon(Icons.check, color: SemColors.accent) : null,
              onTap: () => Navigator.pop(ctx, '|'),
            ),
            for (final t in _terms)
              ListTile(
                title: Text('${t['xnmmc']} · ${_xqName('${t['xqmmc']}')}'),
                trailing: (_xnm == '${t['xnm']}' && _xqm == '${t['xqm']}')
                    ? Icon(Icons.check, color: SemColors.accent)
                    : null,
                onTap: () => Navigator.pop(ctx, '${t['xnm']}|${t['xqm']}'),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final p = picked.split('|');
    final nxnm = p.isNotEmpty ? p[0] : '';
    final nxqm = p.length > 1 ? p[1] : '';
    if (nxnm == _xnm && nxqm == _xqm) return;
    setState(() {
      _xnm = nxnm;
      _xqm = nxqm;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _all;
    final filterLabel = _xnm.isEmpty
        ? '按学年学期筛选'
        : () {
            final t = _terms
                .where((t) => '${t['xnm']}' == _xnm && '${t['xqm']}' == _xqm)
                .firstOrNull;
            return t == null ? '$_xnm ${_xqName(_xqm)}' : '${t['xnmmc']} · ${_xqName('${t['xqmmc']}')}';
          }();
    return Scaffold(
      appBar: AppBar(title: const Text('成绩查询')),
      body: PageStateView(
        loading: _loading,
        error: _err,
        empty: !_loading && _err == null && _all.isEmpty,
        emptyText: '暂无成绩记录',
        onRetry: _load,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            children: [
              AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BigStat(
                      label: '平均绩点',
                      value: _gpa.toStringAsFixed(2),
                      color: SemColors.accent,
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: _pickTerm,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: SemColors.cardElevated,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _xnm.isEmpty ? SemColors.border : SemColors.accent,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(filterLabel,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: _xnm.isEmpty
                                            ? SemColors.textMuted
                                            : SemColors.accent)),
                                const SizedBox(width: 4),
                                Icon(Icons.expand_more, size: 14, color: SemColors.textMuted),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('共 ${_all.length} 门 · 满分绩点 5.0',
                            style: TextStyle(fontSize: 12, color: SemColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              for (final g in list)
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: SemColors.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${g['kcmc']}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600, color: SemColors.textPrimary)),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _chip('${g['kclbmc']}'),
                                  _chip('${g['khfsmc']}'),
                                  _chip('${g['xnmmc']} ${_xqName('${g['xqmmc']}')}'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${g['cj']}',
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: SemColors.accent)),
                            Text('学分 ${g['xf']} · 绩点 ${g['jd']}',
                                style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                          ],
                        ),
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

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: SemColors.neutralSoft,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, color: SemColors.textMuted)),
      );
}
