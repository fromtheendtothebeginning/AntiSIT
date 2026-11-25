import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'credit_math.dart';

/// 「加分明细」页：记录数 / 累计学分 + 搜索与两级标签筛选 + 每条记录的卡片。
Widget buildScoreCredits({
  required double topInset,
  required double tabsRowHeight,
  required List<Map<String, dynamic>> credits,
  required bool loading,
  required String? error,
  required bool fromCache,
  required bool refreshFailed,
  required String query,
  required String dl,
  required String lb,
  required ValueChanged<String> onQueryChanged,
  required ValueChanged<String> onDlChanged,
  required ValueChanged<String> onLbChanged,
  required Future<void> Function() onRefresh,
}) {
  // 学分按「千分位整数」累加再换算回学分：double 直接相加会出现 0.1+0.2 这类浮点尾巴。
  final sum = sumCreditThousandths(credits.map((r) => r['credit'])) / 1000;
  final filtered = filterCreditRecords(credits, query: query, dl: dl, lb: lb);
  final filtering = query.trim().isNotEmpty || dl.isNotEmpty || lb.isNotEmpty;
  return PageStateView(
    loading: loading && credits.isEmpty,
    error: error,
    empty: !loading && error == null && credits.isEmpty,
    emptyText: '暂无加分明细',
    onRetry: onRefresh,
    child: RefreshIndicator(
      // 刷新圈落在悬浮切换器下面，别贴着屏幕最上沿（issue #14）
      edgeOffset: topInset + tabsRowHeight,
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey<String>('score_credits'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          12,
          8 + topInset + tabsRowHeight,
          12,
          20,
        ),
        children: [
          ToolRefreshBar(
            refreshing: loading,
            fromCache: fromCache,
            failed: refreshFailed,
            onRefresh: onRefresh,
          ),
          if (credits.isNotEmpty) ...[
            AppCard(
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '加分记录',
                        style: TextStyle(
                          fontSize: 11,
                          color: SemColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${credits.length} 条',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: SemColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '累计学分',
                        style: TextStyle(
                          fontSize: 11,
                          color: SemColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatCredit(sum),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: SemColors.accent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              onChanged: onQueryChanged,
              decoration: const InputDecoration(
                hintText: '搜索活动名 / 类别，支持拼音…',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TagFilterRow(
              title: '大类',
              labels: creditDlOptions(credits),
              selected: dl,
              onSelected: onDlChanged,
            ),
            const SizedBox(height: 4),
            TagFilterRow(
              title: '类别',
              labels: creditLbOptions(credits, dl),
              selected: lb,
              onSelected: onLbChanged,
            ),
            if (filtering) ...[
              const SizedBox(height: 6),
              Text(
                filtered.isEmpty
                    ? '没有符合条件的记录'
                    : '已筛出 ${filtered.length} / ${credits.length} 条',
                style: TextStyle(fontSize: 11.5, color: SemColors.textMuted),
              ),
            ],
            const SizedBox(height: 6),
          ],
          if (!filtering || filtered.isNotEmpty)
            for (final r in filtered) _creditTile(r),
        ],
      ),
    ),
  );
}

/// 空串 / 'null' 归一成空（学校脏数据里代码位可能回 'null' 字符串）。
String scoreTag(Object? v) {
  final s = '${v ?? ''}'.trim();
  return (s.isEmpty || s == 'null') ? '' : s;
}

/// 明细里出现过的大类（保序去重）。
List<String> creditDlOptions(List<Map<String, dynamic>> records) {
  final seen = <String>{};
  final out = <String>[];
  for (final r in records) {
    final d = scoreTag(r['dldm']);
    if (d.isNotEmpty && seen.add(d)) out.add(d);
  }
  return out;
}

/// 类别选项：选了大类就只列该大类下的（级联）。
List<String> creditLbOptions(
  List<Map<String, dynamic>> records,
  String dl,
) {
  final seen = <String>{};
  final out = <String>[];
  for (final r in records) {
    if (dl.isNotEmpty && scoreTag(r['dldm']) != dl) continue;
    final l = scoreTag(r['lbdm']);
    if (l.isNotEmpty && seen.add(l)) out.add(l);
  }
  return out;
}

/// 筛选后的明细：标签过滤 + 搜索（活动名 / 大类 / 类别，支持拼音）。
List<Map<String, dynamic>> filterCreditRecords(
  List<Map<String, dynamic>> records, {
  required String query,
  required String dl,
  required String lb,
}) {
  final list = records.where((r) {
    if (dl.isNotEmpty && scoreTag(r['dldm']) != dl) return false;
    if (lb.isNotEmpty && scoreTag(r['lbdm']) != lb) return false;
    return true;
  }).toList();
  return filterByPinyin(
    list,
    (r) => '${r['name']} ${scoreTag(r['dldm'])} ${scoreTag(r['lbdm'])}',
    query,
  );
}

/// 一条加分记录卡：学分 / 审批状态 / 分类胶囊 + 活动名 + 时间。
Widget _creditTile(Map<String, dynamic> r) {
  final credit = asNum(r['credit']);
  final status = '${r['status'] ?? ''}'.trim();
  final cat = [
    '${r['dldm'] ?? ''}'.trim(),
    '${r['lbdm'] ?? ''}'.trim(),
  ].where((s) => s.isNotEmpty && s != 'null').join(' · ');
  final start = '${r['start'] ?? ''}'.trim();
  final date = '${r['date'] ?? ''}'.trim();
  final when = start.isNotEmpty ? start : date;
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppCard(
      radius: 10,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (credit != null)
                Capsule(
                  '${formatCredit(credit)} 学分',
                  color: SemColors.accent,
                ),
              if (status.isNotEmpty)
                Capsule(
                  status,
                  color: status.contains('通过')
                      ? SemColors.success
                      : SemColors.textMuted,
                ),
              if (cat.isNotEmpty) Capsule(cat),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${r['name']}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: SemColors.textPrimary,
            ),
          ),
          if (when.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '时间：${_shortTime(when)}',
                style: TextStyle(fontSize: 12, color: SemColors.textMuted),
              ),
            ),
        ],
      ),
    ),
  );
}

String _shortTime(String s) => s.length >= 16 ? s.substring(0, 16) : s;
