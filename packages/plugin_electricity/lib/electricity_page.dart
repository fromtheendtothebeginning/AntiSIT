import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 电费：复刻网站「电费查询」排版（大数字余额 + 充值/刷新 + 历史余额折线图 + 充值弹窗）。
class ElectricityPage extends StatefulWidget {
  const ElectricityPage({super.key});

  @override
  State<ElectricityPage> createState() => _ElectricityPageState();
}

class _ElectricityPageState extends ToolPageState<ElectricityPage> {
  bool _historyLoading = false;
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _history = [];
  int _days = 90;

  static const _queryKey = 'electricity';
  static String _historyKey(int days) => 'electricity.history.$days';

  @override
  String get cacheKey => _queryKey;

  @override
  String get errorTitle => '电费加载失败';

  @override
  bool get hasData => _data != null;

  @override
  bool applyCache(Map<String, dynamic>? cached) {
    final data = (cached?['data'] as Map?)?.cast<String, dynamic>();
    if (data == null) return false;
    _data = data;
    return true;
  }

  @override
  Future<bool> fetchData() async {
    final r = await ApiClient.I.electricityQuery();
    final data = r['data'] as Map<String, dynamic>?;
    _data = data;
    ToolCache.electricity = ToolCache.electricityOf(data);
    await ToolPageCache.write(_queryKey, {'data': data});
    return true;
  }

  /// 电费页有两份缓存（余额 + 历史曲线），基类只认主 key，所以这里自己读两份。
  @override
  Future<void> restore() async {
    final cached = await ToolPageCache.read(_queryKey);
    final cachedHistory = await ToolPageCache.read(_historyKey(_days));
    if (!mounted) return;
    final applied = applyCache(cached);
    final history =
        ((cachedHistory?['records'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (applied || history.isNotEmpty) {
      setState(() {
        _history = history;
        loading = false;
        fromCache = true;
      });
    }
    if (!AppState.I.autoRefreshTools && (_data != null || _history.isNotEmpty)) {
      return;
    }
    await _refreshAll();
  }

  Future<void> _refreshAll() => Future.wait([refresh(), _loadHistory()]);

  Future<void> _loadHistory() async {
    final days = _days;
    setState(() {
      _historyLoading = _history.isEmpty;
      refreshFailed = false;
    });
    try {
      final r = await ApiClient.I.electricityHistory(days: days);
      if (_days != days) return; // 期间切了天数，别把旧请求的结果盖上去
      _history = ((r['records'] as List?) ?? const []).cast<Map<String, dynamic>>();
      await ToolPageCache.write(_historyKey(days), {'records': _history});
    } catch (_) {
      // 历史拉取失败保留已有曲线（查余额本身不受影响）
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  /// 切天数：先显示该天数的本地缓存，再拉新（缓存里没有就转圈等新数据）。
  Future<void> _switchDays(int days) async {
    if (_days == days) return;
    final cached = await ToolPageCache.read(_historyKey(days));
    if (!mounted || _days != days) return;
    final records =
        ((cached?['records'] as List?) ?? const []).cast<Map<String, dynamic>>();
    setState(() {
      _days = days;
      _history = records;
      fromCache = records.isNotEmpty;
    });
    await _loadHistory();
  }

  Future<void> _recharge() async {
    // 风险提醒（默认开启）拦在充值前面：点击只弹提醒，引导去插件管理关掉它
    // （查余额、看历史不受影响）。没装 / 被停用时取不到能力 = 没有这道闸。
    final risk = PluginRegistry.I.capability<RiskNoticeCapability>(PluginIds.risk);
    if (risk != null) {
      await risk.warnBlocked(context, feature: '宿舍电费充值');
      return;
    }
    final balance = asDouble(_data?['balance']);
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('电费充值'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: SemColors.neutralSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '宿舍电费余额：¥${balance?.toStringAsFixed(2) ?? '—'}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 14),
            const Text('充值金额（元）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: '输入充值金额',
                isDense: true,
              ),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 10),
            Text(
              '扣款仅提交一次、绝不自动重试；超时请先查余额确认',
              style: TextStyle(fontSize: 11, color: SemColors.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认充值')),
        ],
      ),
    );
    if (confirmed != true) return;
    final amount = num.tryParse(controller.text.trim());
    if (amount == null || amount < 0.01 || amount > 500) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('金额须在 0.01 - 500 元之间'), behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => loading = true);
    try {
      await ApiClient.I.electricityRecharge(amount);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ 充值成功'), behavior: SnackBarBehavior.floating));
      await refresh(force: true); // 充值成功后必须重拉余额；此时 loading 已被置 true
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiError ? e.message : e.toString();
      final uncertain = msg.contains('超时') || msg.contains('网络');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('充值结果未确认'),
          content: Text(uncertain
              ? '网络异常：$msg\n\n为防重复扣款，本次充值不会自动重试。请稍后在电费查询中确认是否到账。'
              : '充值失败：$msg'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了'))],
        ),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// 对齐网站：按近 7 天日均耗电（remain 度差值 / 天数）推算「预计可用天数」，低于 5 天预警。
  (double avg, double daysLeft)? _usageStats() {
    final remain = asDouble(_data?['remain']);
    if (remain == null || _history.length < 2) return null;
    final now = DateTime.now();
    final recent = _history.where((r) {
      final t = DateTime.tryParse('${r['time']}');
      return t != null && now.difference(t).inDays <= 7;
    }).toList();
    if (recent.length < 2) return null;
    final first = DateTime.tryParse('${recent.first['time']}');
    final last = DateTime.tryParse('${recent.last['time']}');
    final r0 = asDouble(recent.first['remain']);
    final r1 = asDouble(recent.last['remain']);
    if (first == null || last == null || r0 == null || r1 == null) return null;
    final days = last.difference(first).inDays;
    if (days < 1) return null;
    final avg = (r0 - r1) / days;
    if (avg <= 0) return null;
    return (avg, remain / avg);
  }

  @override
  Widget build(BuildContext context) {
    final balance = asDouble(_data?['balance']);
    final card = asDouble(_data?['card_balance']);
    final remain = asDouble(_data?['remain']);
    final low = balance != null && balance < 10;
    final usage = _usageStats();
    return Scaffold(
      appBar: AppBar(title: const Text('宿舍电费')),
      body: PageStateView(
        loading: loading && _data == null,
        error: error,
        onRetry: _refreshAll,
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              ToolRefreshBar(
                refreshing: loading || _historyLoading,
                fromCache: fromCache,
                failed: refreshFailed,
                onRefresh: _refreshAll,
              ),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: BigStat(
                            label: '宿舍电费余额',
                            value: balance == null ? '—' : '¥${balance.toStringAsFixed(2)}',
                            color: low ? SemColors.danger : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        BigStat(
                          label: '校园卡余额',
                          value: card == null ? '—' : '¥${card.toStringAsFixed(2)}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: loading ? null : _recharge,
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          ),
                          child: const Text('充值'),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: loading ? null : refresh,
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          ),
                          child: Text(loading ? '查询中…' : '刷新'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (_data?['dorm'] != null)
                          Capsule('寝室 ${_data?['dorm']}'),
                        if (remain != null) Capsule('剩余电量 $remain 度'),
                        if (usage != null) Capsule('日均 ${usage.$1.toStringAsFixed(1)} 度'),
                        if (usage != null)
                          Capsule(
                            '预计可用 ${usage.$2 < 1 ? '不足 1' : usage.$2.round()} 天',
                            color: usage.$2 < 5 ? SemColors.danger : SemColors.success,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '余额低于 10 元、预计可用不足 5 天会标红；充值走校园卡公网直连',
                  style: TextStyle(fontSize: 11, color: SemColors.textMuted),
                ),
              ),
              const SizedBox(height: 12),
              // 历史余额折线图（新接口 /electricity/history）
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('历史余额',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Text('每天最低余额（元）',
                            style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                        const Spacer(),
                        SizedBox(
                          width: 126,
                          child: GlassTabs(
                            labels: const ['7天', '30天', '90天'],
                            index: const [7, 30, 90].indexOf(_days),
                            onChanged: (i) {
                              final d = const [7, 30, 90][i];
                              _switchDays(d);
                            },
                            height: 28,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_historyLoading)
                      const SizedBox(
                          height: 120,
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                    else
                      BalanceChart(records: _history),
                    const SizedBox(height: 6),
                    Center(
                      child: Text('每晚 22:00 自动查询并记录 · 绿点为当天有充值',
                          style: TextStyle(fontSize: 10.5, color: SemColors.textMuted)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
