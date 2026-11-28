import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'timetable_geometry.dart';

/// 日程筛选条件：时间段（开始不早于 / 结束不晚于，可选）+ 重复类型（多选）+ 日期范围。
///
/// 命中逻辑是「所有已选条件同时满足」（AND）；同一类里多选是 OR。
/// 日期范围的意思是「在这个区间里会发生」：单次日程看它那一天，重复日程看区间里
/// 有没有一次发生（每两周 / 每月都算在内）。
@immutable
class EventFilter {
  const EventFilter({
    this.startFrom = '',
    this.startTo = '',
    this.repeats = const {},
    this.dateFrom = '',
    this.dateTo = '',
  });

  /// 开始时刻不早于（HH:mm，空 = 不限）。
  final String startFrom;

  /// 结束时刻不晚于（HH:mm，空 = 不限）。
  final String startTo;

  /// 重复类型多选（none / weekly / biweekly / monthly）；空 = 不限。
  final Set<String> repeats;

  /// 日期范围（YYYY-MM-DD，可选）：只留这个区间里会发生的日程。
  final String dateFrom;
  final String dateTo;

  static const List<(String, String)> repeatOptions = [
    (TtEvent.repeatNone, '单次'),
    (TtEvent.repeatWeekly, '每周'),
    (TtEvent.repeatBiweekly, '每两周'),
    (TtEvent.repeatMonthly, '每月'),
  ];

  /// 有没有任何一条条件被选中（false = 不过滤）。
  bool get isActive =>
      startFrom.isNotEmpty ||
      startTo.isNotEmpty ||
      repeats.isNotEmpty ||
      dateFrom.isNotEmpty ||
      dateTo.isNotEmpty;

  EventFilter copyWith({
    String? startFrom,
    String? startTo,
    Set<String>? repeats,
    String? dateFrom,
    String? dateTo,
  }) => EventFilter(
    startFrom: startFrom ?? this.startFrom,
    startTo: startTo ?? this.startTo,
    repeats: repeats ?? this.repeats,
    dateFrom: dateFrom ?? this.dateFrom,
    dateTo: dateTo ?? this.dateTo,
  );

  /// 这条日程是否命中全部已选条件。
  bool matches(TtEvent e, SemesterTt tt) {
    if (!isActive) return true;
    if (repeats.isNotEmpty && !repeats.contains(e.repeat)) return false;
    final sm = hm(e.start);
    final em = hm(e.end);
    final fromMin = hm(startFrom);
    final toMin = hm(startTo);
    // 全天日程（没写时刻）按 00:00–23:59 摆，时段条件照样判得出来。
    final eStart = sm < 0 ? 0 : sm;
    final eEnd = em < 0 ? 1439 : em;
    if (fromMin >= 0 && eStart < fromMin) return false;
    if (toMin >= 0 && eEnd > toMin) return false;
    if (dateFrom.isNotEmpty || dateTo.isNotEmpty) {
      final df = DateTime.tryParse(dateFrom);
      final dt = DateTime.tryParse(dateTo);
      final from = df == null
          ? DateTime(1970)
          : DateTime(df.year, df.month, df.day);
      final to = dt == null
          ? DateTime(2100)
          : DateTime(dt.year, dt.month, dt.day);
      if (!TimetableStore.eventOccursBetween(tt, e, from, to)) return false;
    }
    return true;
  }

  /// 条件摘要（筛选生效提示条 / 筛选面板顶部用）；空条件返回空串。
  String get summary => [
    if (startFrom.isNotEmpty || startTo.isNotEmpty)
      '${startFrom.isEmpty ? '不限' : startFrom}–${startTo.isEmpty ? '不限' : startTo}',
    if (repeats.isNotEmpty)
      [
        for (final (v, l) in repeatOptions)
          if (repeats.contains(v)) l,
      ].join('/'),
    if (dateFrom.isNotEmpty || dateTo.isNotEmpty)
      '${_shortDate(dateFrom, '最早')}~${_shortDate(dateTo, '不限')}',
  ].join(' · ');

  static String _shortDate(String iso, String empty) {
    if (iso.isEmpty) return empty;
    return iso.length >= 10 ? iso.substring(5).replaceAll('-', '/') : iso;
  }
}

/// 按当前筛选条件挑出命中（或全部）日程，供页面统一传下去。
List<TtEvent> filterEvents(SemesterTt tt, {EventFilter? filter}) {
  final f = filter;
  if (f == null || !f.isActive) return tt.events;
  return [
    for (final e in tt.events)
      if (f.matches(e, tt)) e,
  ];
}

/// 打开筛选面板；null = 取消（保留原条件），非 null = 应用 / 清除后的条件。
Future<EventFilter?> showEventFilterSheet(
  BuildContext context, {
  required SemesterTt tt,
  EventFilter? initial,
}) async {
  var draft = initial ?? const EventFilter();
  final saved = await showModalBottomSheet<EventFilter>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        Future<void> pickTime({required bool start}) async {
          final cur = hm(start ? draft.startFrom : draft.startTo);
          final t = await showGlassTimePicker(ctx,
            initialTime: TimeOfDay(
              hour: cur < 0 ? (start ? 8 : 22) : cur ~/ 60,
              minute: cur < 0 ? 0 : cur % 60,
            ),
            title: start ? '开始时间不早于' : '结束时间不晚于',
          );
          if (t == null) return;
          final hhmm =
              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
          setS(
            () => draft = start
                ? draft.copyWith(startFrom: hhmm)
                : draft.copyWith(startTo: hhmm),
          );
        }

        Future<void> pickDate({required bool from}) async {
          final now = DateTime.now();
          final cur = DateTime.tryParse(from ? draft.dateFrom : draft.dateTo);
          final picked = await showGlassDatePicker(ctx,
            initialDate: cur ?? now,
            firstDate: DateTime(now.year - 2),
            lastDate: DateTime(now.year + 2),
            title: from ? '只看这一天之后会发生的' : '只看这一天之前会发生的',
          );
          if (picked == null) return;
          final iso = TimetableStore.iso(picked);
          setS(
            () => draft = from
                ? draft.copyWith(dateFrom: iso)
                : draft.copyWith(dateTo: iso),
          );
        }

        final hit = filterEvents(tt, filter: draft).length;
        final total = tt.events.length;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              16 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.86,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '筛选日程',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      '已选条件同时生效：命中 $hit / $total 条日程'
                      "${draft.isActive ? '' : '（当前未筛选）'}",
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.6,
                        color: hit == 0 && draft.isActive
                            ? SemColors.danger
                            : SemColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('时间段（按日程自身的开始 / 结束时刻）', style: _sectionStyle),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _pickChip(
                            label: '开始 ≥',
                            value: draft.startFrom,
                            empty: '不限',
                            onTap: () => pickTime(start: true),
                            onClear: draft.startFrom.isEmpty
                                ? null
                                : () => setS(
                                    () => draft = draft.copyWith(startFrom: ''),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _pickChip(
                            label: '结束 ≤',
                            value: draft.startTo,
                            empty: '不限',
                            onTap: () => pickTime(start: false),
                            onClear: draft.startTo.isEmpty
                                ? null
                                : () => setS(
                                    () => draft = draft.copyWith(startTo: ''),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('重复类型（可多选）', style: _sectionStyle),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (v, l) in EventFilter.repeatOptions)
                          FilterChip(
                            label: Text(
                              l,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            selected: draft.repeats.contains(v),
                            onSelected: (on) {
                              final next = {...draft.repeats};
                              if (on) {
                                next.add(v);
                              } else {
                                next.remove(v);
                              }
                              setS(() => draft = draft.copyWith(repeats: next));
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('日期范围（只看这个区间里会发生的）', style: _sectionStyle),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _pickChip(
                            label: '从',
                            value: draft.dateFrom,
                            empty: '不限',
                            onTap: () => pickDate(from: true),
                            onClear: draft.dateFrom.isEmpty
                                ? null
                                : () => setS(
                                    () => draft = draft.copyWith(dateFrom: ''),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _pickChip(
                            label: '到',
                            value: draft.dateTo,
                            empty: '不限',
                            onTap: () => pickDate(from: false),
                            onClear: draft.dateTo.isEmpty
                                ? null
                                : () => setS(
                                    () => draft = draft.copyWith(dateTo: ''),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    if (draft.isActive && hit == 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: SemColors.dangerSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '没有符合条件的日程：放宽时段或日期范围试试',
                          style: TextStyle(
                            fontSize: 12,
                            color: SemColors.danger,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () =>
                              setS(() => draft = const EventFilter()),
                          child: const Text('重置条件'),
                        ),
                        const Spacer(),
                        OutlinedButton(
                          onPressed: () =>
                              Navigator.pop(ctx, const EventFilter()),
                          child: const Text('清除筛选'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, draft),
                          child: Text(draft.isActive ? '应用（$hit 条）' : '应用'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
  return saved;
}

final TextStyle _sectionStyle = TextStyle(
  fontSize: 12.5,
  color: SemColors.textSecondary,
);

/// 顶栏下方的「筛选生效中」提示条：点一下清掉筛选，右侧显示命中条数。
Widget buildEventFilterBanner({
  required EventFilter filter,
  required int hit,
  required int total,
  required VoidCallback onClear,
}) => Container(
  width: double.infinity,
  margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  decoration: BoxDecoration(
    color: SemColors.infoSoft,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: SemColors.info.withValues(alpha: 0.3)),
  ),
  child: InkWell(
    onTap: onClear,
    borderRadius: BorderRadius.circular(10),
    child: Row(
      children: [
        Icon(Icons.filter_alt_rounded, size: 15, color: SemColors.info),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '筛选生效中 · 命中 $hit / $total 条 · ${filter.summary}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: SemColors.info, height: 1.5),
          ),
        ),
        const SizedBox(width: 8),
        Text('清除', style: TextStyle(fontSize: 12, color: SemColors.info)),
      ],
    ),
  ),
);

/// 筛选面板里的一枚日期 / 时间胶囊：点选，右侧小叉清空。
Widget _pickChip({
  required String label,
  required String value,
  required String empty,
  required VoidCallback onTap,
  required VoidCallback? onClear,
}) {
  return InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: SemColors.inputFill,
        border: Border.all(
          color: value.isEmpty
              ? SemColors.border
              : SemColors.accent.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value.isEmpty ? '$label $empty' : '$label $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: value.isEmpty
                    ? SemColors.textMuted
                    : SemColors.textPrimary,
              ),
            ),
          ),
          if (onClear != null)
            GestureDetector(
              onTap: onClear,
              behavior: HitTestBehavior.opaque,
              child: Icon(Icons.close, size: 15, color: SemColors.textMuted),
            ),
        ],
      ),
    ),
  );
}
