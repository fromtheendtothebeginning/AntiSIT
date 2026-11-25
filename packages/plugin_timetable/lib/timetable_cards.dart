import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'timetable_geometry.dart';

/// 顶部「今天」卡：今天第几周、调休说明与最近一节课。
Widget buildTodayCard({
  required SemesterTt tt,
  required int? todayWeek,
  required List<TtCourse> allCourses,
  required VoidCallback onOpenSemesterSettings,
}) {
  final now = DateTime.now();
  final tw = todayWeek;
  final noStart = tt.startDate.isEmpty;
  // 调休规则同样作用于今天：off → 无课，follow → 按被借星期的课表
  final adj = tw == null ? null : columnAdjust(tt, tw, now.weekday - 1);
  final effDay =
      adj == null ? now.weekday - 1 : (adj.type == 'off' ? null : adj.day);
  List<TtCourse> courses = const [];
  if (tw != null && effDay != null) {
    courses = allCourses
        .where((c) => TimetableStore.coversWeek(c, tw) && c.day == effDay)
        .toList()
      ..sort((a, b) => a.slotStart.compareTo(b.slotStart));
  }
  // 判「上完没有」要用今天这一列的真实日期：调休补课时 effDay 是被借的星期，
  // 拿被借那天的日期去比会把今天的课全判成已上完，卡片就一片空白。
  final upcoming = (tw == null || effDay == null)
      ? courses
      : TimetableStore.upcomingOn(
          courses,
          startDate: tt.startDate,
          week: tw,
          dayIndex: now.weekday - 1,
          endTimes: TimetableStore.slotEnds,
          now: now,
        );
  final next = upcoming.isEmpty ? null : upcoming.first;
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
    child: AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.today_rounded, size: 15, color: SemColors.accent),
              const SizedBox(width: 6),
              Text(
                noStart
                    ? '未设置学期起点'
                    : tw == null
                        ? '假期中（学期外）'
                        : '今天 · 第$tw周',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (noStart)
                GestureDetector(
                  onTap: onOpenSemesterSettings,
                  child: Text(
                    '去设置',
                    style: TextStyle(fontSize: 12, color: SemColors.accent),
                  ),
                )
              else
                Text(
                  adj?.type == 'off'
                      ? '放假（调休）'
                      : (adj?.type == 'follow'
                          ? '按周${'一二三四五六日'[adj!.day]}上课'
                          : (courses.isEmpty
                              ? '今天没有课'
                              : (next == null
                                  ? '今天的课都上完了'
                                  : '还剩 ${upcoming.length} 节'))),
                  style: TextStyle(
                    fontSize: 12,
                    color: adj?.type == 'off'
                        ? SemColors.danger
                        : SemColors.textMuted,
                  ),
                ),
            ],
          ),
          if (!noStart && tw != null && next != null) ...[
            const SizedBox(height: 8),
            _nextClassRow(next, now, tt, tw),
          ],
        ],
      ),
    ),
  );
}

/// 今天这一列的真实日期（yyyy-MM-dd）；学期起点未设置时返回空串。
String _todayISO(SemesterTt tt, int? todayWeek) {
  final tw = todayWeek;
  if (tw == null) return '';
  return columnISO(tt, tw, DateTime.now().weekday - 1);
}

/// 今天最近一节还没上完的课（时间、节次、地点；正在上的标「正在上课」）。
Widget _nextClassRow(TtCourse c, DateTime now, SemesterTt tt, int todayWeek) {
  final from = TimetableStore.slotStarts[c.slotStart.clamp(0, 10)];
  final to = TimetableStore.slotEnds[c.slotEnd.clamp(0, 10)];
  final colISO = _todayISO(tt, todayWeek);
  // 正在上课 = 已到上课时刻且还没下课（只看「没下课」会把还没开始的课也标成正在上）。
  final inClass = colISO.isNotEmpty &&
      TimetableStore.lessonPassed(colISO, from, now: now) &&
      !TimetableStore.lessonPassed(colISO, to, now: now);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: courseBlockColor(c.name),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 86,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                from,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                to,
                style: TextStyle(fontSize: 10, color: SemColors.textMuted),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      c.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (inClass) ...[
                    const SizedBox(width: 6),
                    // 玻璃化：底色很淡 + 文字半透明 + 细描边，压在课程色块上不抢主体
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: SemColors.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: SemColors.accent.withValues(alpha: 0.25),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '正在上课',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: SemColors.accent.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                '第${c.slotStart + 1}-${c.slotEnd + 1}节'
                '${c.place.isEmpty ? '' : ' · ${c.place}'}'
                '${c.teachers.isEmpty ? '' : ' · ${c.teachers}'}',
                style: TextStyle(
                  fontSize: 11,
                  color: SemColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 近期考试 / 日程提醒条：全局信息，不随左右切周变化；没有日程时不占位。
Widget buildExamStrip({required SemesterTt tt}) {
  final now = DateTime.now();
  final day0 = DateTime(now.year, now.month, now.day);
  final upcoming = <(TtEvent, int)>[];
  for (final e in tt.events) {
    final d = DateTime.tryParse(e.date);
    if (d == null) continue;
    final diff = DateTime(d.year, d.month, d.day).difference(day0).inDays;
    if (diff >= 0 && diff <= 90) upcoming.add((e, diff));
  }
  if (upcoming.isEmpty) return const SizedBox.shrink();
  upcoming.sort((a, b) => a.$2.compareTo(b.$2));
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
    child: AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                upcoming.first.$1.kind == 'exam'
                    ? Icons.event_note_rounded
                    : Icons.schedule_rounded,
                size: 15,
                color: SemColors.danger,
              ),
              const SizedBox(width: 6),
              const Text(
                '近期日程',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              Text(
                '${upcoming.length} 项',
                style: TextStyle(fontSize: 12, color: SemColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: math.min(5, upcoming.length),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final (e, diff) = upcoming[i];
                // 今天已经结束的那条也压暗（列表本身只列今天及以后）
                return Opacity(
                  opacity: eventIsPast(e, e.date) && AppState.I.dimCompleted
                      ? 0.55
                      : 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: SemColors.dangerSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${e.name} ${e.date.substring(5)} '
                      '${diff == 0 ? '今天' : diff == 1 ? '明天' : '还有$diff天'}',
                      style: TextStyle(fontSize: 12, color: SemColors.danger),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

/// 日视图某一天的内容（不含顶部两块）；竖向滚动由外层统一负责。
Widget buildDayBody({
  required SemesterTt tt,
  required List<TtCourse> allCourses,
  required int week,
  required int day,
  required int? todayWeek,
  required void Function(TtCourse course, int week) onCourseTap,
  required ValueChanged<TtEvent> onEventTap,
}) {
  final colISO = columnISO(tt, week, day);
  final adj = columnAdjust(tt, week, day);
  final eff = adj == null ? day : (adj.type == 'off' ? null : adj.day);
  final courses = (eff == null
      ? <TtCourse>[]
      : allCourses
          .where(
            (c) => c.day == eff && TimetableStore.coversWeek(c, week),
          )
          .toList())
    ..sort((a, b) => a.slotStart.compareTo(b.slotStart));
  final events = tt.events
      .where(
        (e) =>
            e.date.isEmpty ? (eff != null && e.day == eff) : e.date == colISO,
      )
      .toList()
    ..sort((a, b) => hm(a.start).compareTo(hm(b.start)));

  final isToday = todayWeek == week && day == DateTime.now().weekday - 1;
  final dateText = colISO.isEmpty
      ? '第 $week 周'
      : '${int.tryParse(colISO.substring(5, 7)) ?? ''}月${int.tryParse(colISO.substring(8)) ?? ''}日';

  final items = <(int, Widget)>[
    for (final c in courses)
      (
        hm(TimetableStore.slotStarts[c.slotStart.clamp(0, 10)]),
        _dayCourseCard(c, week, colISO, onCourseTap),
      ),
    for (final e in events)
      (
        hm(e.start) < 0 ? 0 : hm(e.start),
        _dayEventCard(e, colISO, onEventTap),
      ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));

  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              '$dateText 周${'一二三四五六日'[day]}',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            if (isToday) Capsule('今天', color: SemColors.accent),
          ],
        ),
        if (adj != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: adj.type == 'off'
                  ? SemColors.dangerSoft
                  : SemColors.infoSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              adj.type == 'off'
                  ? '放假（调休规则：当天无课）'
                  : '按周${'一二三四五六日'[adj.day]}的课表上课（调休规则）',
              style: TextStyle(
                fontSize: 12.5,
                color: adj.type == 'off' ? SemColors.danger : SemColors.info,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Column(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 44,
                  color: SemColors.textMuted,
                ),
                const SizedBox(height: 10),
                Text(
                  adj?.type == 'off' ? '放假中，当天无课' : '当天没有安排',
                  style: TextStyle(color: SemColors.textMuted),
                ),
              ],
            ),
          )
        else
          ...items.map((it) => it.$2),
      ],
    ),
  );
}

/// 日视图的一天里的一节课卡（已上完的压暗）。
Widget _dayCourseCard(
  TtCourse c,
  int week,
  String colISO,
  void Function(TtCourse course, int week) onCourseTap,
) {
  final past = courseIsPast(c, colISO) && AppState.I.dimCompleted;
  final rs = c.slotStart.clamp(0, 10);
  final re = c.slotEnd.clamp(0, 10);
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Opacity(
      opacity: past ? 0.55 : 1,
      child: AppCard(
        onTap: () => onCourseTap(c, week),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: courseBlockColor(c.name),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    TimetableStore.slotStarts[rs],
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    TimetableStore.slotEnds[re],
                    style: TextStyle(
                      fontSize: 10,
                      color: SemColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '第${c.slotStart + 1}-${c.slotEnd + 1}节 · ${c.weekStart}-${c.weekEnd}周${weekTypeLabel(c.weekType)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: SemColors.textMuted,
                    ),
                  ),
                  if (c.place.isNotEmpty || c.teachers.isNotEmpty)
                    Text(
                      [
                        if (c.place.isNotEmpty) c.place,
                        if (c.teachers.isNotEmpty) c.teachers,
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: SemColors.textSecondary,
                      ),
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

/// 日视图的一天里的一个日程 / 考试卡（结束后整体压暗）。
Widget _dayEventCard(
  TtEvent e,
  String colISO,
  ValueChanged<TtEvent> onEventTap,
) {
  final isExam = e.kind == 'exam';
  final past = eventIsPast(e, colISO) && AppState.I.dimCompleted;
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Opacity(
      opacity: past ? 0.55 : 1,
      child: AppCard(
        onTap: () => onEventTap(e),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isExam ? SemColors.dangerSoft : SemColors.accentSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    e.start.isEmpty ? '—' : e.start,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isExam ? SemColors.danger : SemColors.accent,
                    ),
                  ),
                  if (e.end.isNotEmpty)
                    Text(
                      e.end,
                      style: TextStyle(
                        fontSize: 10,
                        color: SemColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isExam
                                ? SemColors.danger
                                : SemColors.textPrimary,
                          ),
                        ),
                      ),
                      if (e.date.isEmpty)
                        Capsule('每周', color: SemColors.info),
                    ],
                  ),
                  if (e.place.isNotEmpty)
                    Text(
                      e.place,
                      style: TextStyle(
                        fontSize: 12,
                        color: SemColors.textSecondary,
                      ),
                    ),
                  if (e.note.isNotEmpty)
                    Text(
                      e.note,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: SemColors.textMuted,
                      ),
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
