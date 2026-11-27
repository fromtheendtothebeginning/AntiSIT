import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 二课新活动提醒设置：开关 + 按分类（大类 / 小类）挑选要提醒的活动。
///
/// 检查本身由 [ActivityWatchService] 负责；这里只管规则与状态展示。
class ActivityWatchSettingsPage extends StatefulWidget {
  const ActivityWatchSettingsPage({super.key});

  @override
  State<ActivityWatchSettingsPage> createState() =>
      _ActivityWatchSettingsPageState();
}

class _ActivityWatchSettingsPageState extends State<ActivityWatchSettingsPage> {
  /// 可选分类（打开页面时从活动看板拉一次；拉不到就用上次缓存）。
  List<String> _dl = const [];
  List<String> _lb = const [];
  bool _loading = true;
  String? _err;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  /// 分类来自活动看板：先读工具页缓存立即出选项，再后台拉最新（失败保留缓存）。
  Future<void> _loadCategories() async {
    final cached = await ToolPageCache.read('activities');
    _applyList((cached?['data'] as Map?)?['activities']);
    try {
      final r = await ApiClient.I.activities();
      _applyList((r['data'] as Map?)?['activities']);
      _err = null;
    } catch (e) {
      if (_dl.isEmpty && _lb.isEmpty) {
        _err = e is ApiError ? e.message : e.toString();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyList(Object? raw) {
    final list = (raw as List?) ?? const [];
    final dl = <String>{};
    final lb = <String>{};
    for (final a in list) {
      if (a is! Map) continue;
      final d = '${a['dlmc'] ?? ''}'.trim();
      final l = '${a['lbmc'] ?? ''}'.trim();
      if (d.isNotEmpty && d != 'null') dl.add(d);
      if (l.isNotEmpty && l != 'null') lb.add(l);
    }
    if (!mounted) return;
    setState(() {
      _dl = dl.toList();
      _lb = lb.toList();
    });
  }

  /// 立刻按当前规则查一次（第一次检查只建基线，不会提醒历史活动）。
  Future<void> _checkNow() async {
    setState(() => _checking = true);
    final r = await ActivityWatchService.I.check();
    if (!mounted) return;
    setState(() => _checking = false);
    final text = r.error != null
        ? '检查失败：${r.error}'
        : (r.firstRun
              ? '已记录 ${r.fetched} 个活动作为基线，之后出现新活动才会提醒'
              : '共 ${r.fetched} 个活动，命中 ${r.matched.length} 个新活动');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = glassTopInset(context);
    return ListenableBuilder(
      listenable: ActivityWatchService.I,
      builder: (context, _) {
        final svc = ActivityWatchService.I;
        final rule = svc.rule;
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(
            context,
            title: const Text('二课新活动提醒'),
            actions: [
              if (svc.enabled)
                IconButton(
                  tooltip: '立即检查',
                  onPressed: _checking ? null : _checkNow,
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
          body: GlassFadedBody(
            barHeight: topInset,
            child: ListView(
              padding: EdgeInsets.fromLTRB(12, 4 + topInset, 12, 24),
              children: [
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SwitchListTile(
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: const Text('新活动提醒'),
                    subtitle: Text(
                      svc.enabled ? '每小时检查一次，选中的分类出现新活动就弹通知' : '已关闭',
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: svc.enabled,
                    onChanged: (v) => svc.setEnabled(v),
                  ),
                ),
                if (rule.needsCategories)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
                    child: Text(
                      '还没选分类：先选「大类」或「小类」，否则任何新活动都会提醒。',
                      style: TextStyle(fontSize: 11.5, color: SemColors.warning),
                    ),
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_err != null && _dl.isEmpty && _lb.isEmpty)
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '分类加载失败：$_err',
                          style: TextStyle(
                            fontSize: 12,
                            color: SemColors.danger,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _loadCategories,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                else ...[
                  AppCard(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '一级类别',
                          style: TextStyle(
                            fontSize: 12,
                            color: SemColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final d in _dl)
                              InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: () => svc.toggleDl(d),
                                child: Capsule(
                                  d,
                                  color: rule.dl.contains(d)
                                      ? SemColors.accent
                                      : SemColors.textMuted,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '二级类别',
                          style: TextStyle(
                            fontSize: 12,
                            color: SemColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final l in _lb)
                              InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: () => svc.toggleLb(l),
                                child: Capsule(
                                  l,
                                  color: rule.lb.contains(l)
                                      ? SemColors.accent
                                      : SemColors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (svc.lastCheck != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                      child: Text(
                        '上次检查：${_hm(svc.lastCheck!)}'
                        '（${svc.lastFetched} 个活动，命中 ${svc.lastMatched} 个新活动）'
                        '${svc.lastError == null ? '' : ' · 失败：${svc.lastError}'}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: SemColors.textMuted,
                        ),
                      ),
                    ),
                ],
                const PageNotes(
                  lines: [
                    '只按分类筛选：同时选了大类与小类时，活动要两者都命中才会提醒。',
                    '第一次开启后先记录现有活动作为基线，不会把历史活动全部提醒一遍。',
                    '后台检查由系统定时任务执行（约每小时一次），省电策略严格的机型可能延后。',
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _hm(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}
