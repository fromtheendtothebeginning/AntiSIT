import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'timetable_blocks.dart';
import 'timetable_geometry.dart';

/// 周视图某一周的格子（不含顶部「今天」卡与近期日程条，它们在分页之外）。
Widget buildWeekGrid({
  required SemesterTt tt,
  required int week,
  required int? todayWeek,
  required List<TtCourse> allCourses,
  required bool loggedIn,
  required bool directMode,
  required bool loading,
  required void Function(TtCourse course, int week) onCourseTap,
  required ValueChanged<TtEvent> onEventTap,

  /// 页面级日程筛选（null = 全放行）；命中的才算这一列有日程。
  bool Function(TtEvent)? eventFilter,
}) {
  final dates = _datesOf(tt, week);
  final todayIdx = todayWeek == week ? DateTime.now().weekday - 1 : -1;
  final shown = tt.events.where((e) => eventFilter?.call(e) ?? true).toList();
  final hasAny = allCourses.isNotEmpty || shown.isNotEmpty;
  if (!hasAny && loading) {
    return const Center(child: CircularProgressIndicator());
  }
  if (!hasAny && !loggedIn && week == 1) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.edit_calendar_outlined,
            size: 40,
            color: SemColors.textMuted,
          ),
          const SizedBox(height: 8),
          Text('还没有课程', style: TextStyle(color: SemColors.textMuted)),
          const SizedBox(height: 4),
          Text(
            directMode
                ? '点右上角 + 手动添加，或在连接设置填好凭据后从教务导入'
                : '点右上角 + 手动添加，或登录后从教务导入',
            style: TextStyle(fontSize: 12, color: SemColors.textMuted),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
        child: Container(
          decoration: BoxDecoration(
            color: SemColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SemColors.border),
          ),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            height: kHeaderH + weekGridHeight + 8,
            child: Column(
              children: [
                _dayHeaders(tt, week, dates, todayIdx),
                Expanded(
                  child: Stack(
                    children: [
                      // 中午细线（11:55）
                      Positioned(
                        top: kBandH + 4 * kSlotH + kNoonH / 2 - 0.5,
                        left: 0,
                        right: 0,
                        child: Row(
                          children: [
                            SizedBox(
                              width: kAxisW,
                              child: Text(
                                '11:55',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 8,
                                  color: SemColors.textMuted,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: SemColors.border,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 节次轴
                      Positioned(
                        left: 0,
                        top: 0,
                        width: kAxisW,
                        height: weekGridHeight,
                        child: Column(
                          children: [
                            for (final group in const [
                              [0, 1, 2, 3],
                              [4, 5, 6, 7],
                              [8, 9, 10],
                            ]) ...[
                              for (final row in group)
                                SizedBox(
                                  width: kAxisW,
                                  height: kSlotH,
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${row + 1}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: SemColors.textMuted,
                                          ),
                                        ),
                                        Text(
                                          TimetableStore.slotStarts[row],
                                          style: TextStyle(
                                            fontSize: 7.5,
                                            color: SemColors.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (group != const [8, 9, 10])
                                SizedBox(
                                  width: kAxisW,
                                  height:
                                      kBandH +
                                      (group == const [0, 1, 2, 3]
                                          ? kNoonH
                                          : 0) +
                                      (group == const [4, 5, 6, 7] ? kGapH : 0),
                                ),
                            ],
                          ],
                        ),
                      ),
                      // 7 天列（调休规则在渲染层生效）
                      Positioned(
                        left: kAxisW,
                        right: 0,
                        top: 0,
                        height: weekGridHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(7, (di) {
                            final eff = columnEffectiveDay(tt, week, di);
                            final dayCourses = eff == null
                                ? const <TtCourse>[]
                                : allCourses
                                      .where(
                                        (c) =>
                                            c.day == eff &&
                                            TimetableStore.coversWeek(c, week),
                                      )
                                      .toList();
                            // 按开始时刻排序：后开始的后画，真重叠时压在上层。
                            // 日程按自己的重复规则判「这一天有没有」；不看调休
                            // （调休换的是上哪天的课），再套上页面级的筛选条件。
                            final dayEvents =
                                shown
                                    .where(
                                      (e) =>
                                          eventOccursInColumn(tt, e, week, di),
                                    )
                                    .toList()
                                  ..sort(
                                    (a, b) =>
                                        hm(a.start).compareTo(hm(b.start)),
                                  );
                            return Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    // 与卡片外框同色，别额外加透明度，否则浅色主题下像一条跳出来的分割线
                                    left: BorderSide(
                                      color: SemColors.border,
                                      style: BorderStyle.solid,
                                    ),
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    for (final c in dayCourses)
                                      buildCourseBlock(
                                        course: c,
                                        colISO: columnISO(tt, week, di),
                                        onTap: () => onCourseTap(c, week),
                                      ),
                                    for (final e in dayEvents)
                                      ...buildEventBlocks(
                                        event: e,
                                        colISO: columnISO(tt, week, di),
                                        // 真重叠的日程改用不透明底色，避免文字互相透上来
                                        solid: eventOverlaps(
                                          e,
                                          dayEvents,
                                          dayCourses,
                                        ),
                                        onTap: () => onEventTap(e),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      // 时段色带最后绘制：盖在天分隔竖线上方，且不进入左侧时间列
                      _band(0, '上午'),
                      _band(kBandH + 4 * kSlotH + kNoonH, '下午'),
                      _band(
                        kBandH +
                            4 * kSlotH +
                            kNoonH +
                            kBandH +
                            4 * kSlotH +
                            kGapH,
                        '晚上',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// 当周 7 天的日期标签（MM/DD）；未设学期起点时为空串。
List<String> _datesOf(SemesterTt tt, int week) {
  if (tt.startDate.isEmpty) return List.filled(7, '');
  return [
    for (var di = 0; di < 7; di++)
      columnISO(tt, week, di).substring(5).replaceAll('-', '/'),
  ];
}

/// 表头：左边月份，右边 7 天的星期与日期（今天高亮，调休列换色）。
Widget _dayHeaders(SemesterTt tt, int week, List<String> dates, int todayIdx) {
  final monthLabel = dates.isEmpty || dates.first.isEmpty
      ? ''
      : '${int.tryParse(dates.first.split('/')[0]) ?? ''}月';
  return SizedBox(
    height: kHeaderH,
    child: Row(
      children: [
        SizedBox(
          width: kAxisW,
          child: Text(
            monthLabel,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9, color: SemColors.textMuted),
          ),
        ),
        Expanded(
          child: Row(
            children: List.generate(7, (i) {
              final isToday = i == todayIdx;
              final adj = columnAdjust(tt, week, i);
              final wdColor = adj == null
                  ? (isToday ? SemColors.accent : SemColors.textPrimary)
                  : (adj.type == 'off' ? SemColors.danger : SemColors.info);
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: isToday ? SemColors.accentStrong : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '周${'一二三四五六日'[i]}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: wdColor,
                          ),
                        ),
                        Text(
                          dates.isEmpty
                              ? '-'
                              : (dates[i].isEmpty ? '-' : dates[i]),
                          style: TextStyle(
                            fontSize: 10,
                            color: isToday
                                ? SemColors.accent
                                : SemColors.textMuted.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    ),
  );
}

/// 时段色带（上午 / 下午 / 晚上）：不进最左时间列。
Widget _band(double top, String label) => Positioned(
  top: top,
  left: kAxisW,
  right: 0,
  height: kBandH,
  child: Container(
    color: SemColors.stripe,
    alignment: Alignment.center,
    child: Text(
      label,
      style: TextStyle(
        fontSize: 9,
        letterSpacing: 2,
        color: SemColors.textMuted,
      ),
    ),
  ),
);
