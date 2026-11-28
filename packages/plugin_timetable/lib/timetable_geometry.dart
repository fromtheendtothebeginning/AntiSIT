import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 周视图网格的固定尺寸：节次轴宽、单节高、时段色带高、午休、晚饭空档、表头。
const double kAxisW = 30.0;
const double kSlotH = 56.0;
const double kBandH = 20.0;
const double kNoonH = 12.0;

/// 16:30–18:00 没有节次（晚饭空档）：留一行给该时段的日程，否则保存了也看不见。
const double kGapH = 48.0;
const double kHeaderH = 44.0;

/// 第 [row] 节（0-10）在网格里的 y 坐标（含午休与晚饭空档）。
double weekRowY(int row) {
  if (row <= 3) return kBandH + row * kSlotH;
  if (row <= 7) {
    return kBandH + 4 * kSlotH + kNoonH + kBandH + (row - 4) * kSlotH;
  }
  return kBandH +
      4 * kSlotH +
      kNoonH +
      kBandH +
      4 * kSlotH +
      kGapH +
      kBandH +
      (row - 8) * kSlotH;
}

/// 11 节网格的总高度。
double get weekGridHeight => weekRowY(10) + kSlotH;

/// 周视图分页的固定高度：外框上下 4+4 + 卡片内边距 8 + 表头 + 网格。
double get weekPagerHeight => kHeaderH + weekGridHeight + 8 + 16 + 4;

/// 当周某列（0=周一）的日期 ISO；未设学期起点返回空串。
String columnISO(SemesterTt tt, int week, int dayIndex) {
  if (tt.startDate.isEmpty) return '';
  return TimetableStore.iso(
    TimetableStore.dateOfWeekDay(tt.startDate, week, dayIndex),
  );
}

/// 该列的调休规则：按日期命中，同一天只会命中一条。
TtAdjust? columnAdjust(SemesterTt tt, int week, int dayIndex) {
  final iso = columnISO(tt, week, dayIndex);
  if (iso.isEmpty) return null;
  for (final a in tt.adjustments) {
    if (a.date == iso) return a;
  }
  return null;
}

/// 该列实际按星期几的课表上课；off 放假返回 null。
int? columnEffectiveDay(SemesterTt tt, int week, int dayIndex) {
  final a = columnAdjust(tt, week, dayIndex);
  if (a == null) return dayIndex;
  return a.type == 'off' ? null : a.day;
}

/// 某列（某周某天）这一天，这条日程是否发生。
///
/// 判据与课表页老行为一致：每周 / 每两周重复的日程跟着这一列「实际上的是星期几」
/// 走（调休 follow 按被借的星期出现，off 那天不出现）；每月重复锚在日期上，不看调休。
/// 学期起点没设时判不出日期，只有重复日程还能按星期几显示。
bool eventOccursInColumn(SemesterTt tt, TtEvent e, int week, int dayIndex) {
  if (tt.startDate.isEmpty) return e.isRepeating && e.day == dayIndex;
  final date = TimetableStore.dateOfWeekDay(tt.startDate, week, dayIndex);
  return e.occursOnColumn(
    date,
    semesterStart: TimetableStore.semesterStartOf(tt) ?? date,
    weekdayOverride: columnEffectiveDay(tt, week, dayIndex),
  );
}

/// 分段次的公共判据：'HH:mm' → 一天中的分钟，格式不对返回 -1。
int hm(String s) {
  final p = s.split(':');
  if (p.length != 2) return -1;
  return (int.tryParse(p[0]) ?? -1) * 60 + (int.tryParse(p[1]) ?? -1);
}

/// 周次类型（all / odd / even）的中文名。
String weekTypeLabel(String t) => switch (t) {
  'odd' => '单周',
  'even' => '双周',
  _ => '每周',
};

/// 与网站一致：课名哈希 → 5 色相（蓝紫/青绿/橙/绿/粉）。
const List<double> _courseHues = [258.0, 174.0, 25.0, 145.0, 335.0];

/// 课程块底色：深色下提亮提饱和，浅色下 16% 透明度。
Color courseBlockColor(String name) {
  var h = 0;
  for (final ch in name.codeUnits) {
    h = (h * 31 + ch) % 100000;
  }
  final hue = _courseHues[h % _courseHues.length];
  return SemColors.isDark
      ? HSLColor.fromAHSL(0.30, hue, 0.55, 0.68).toColor()
      : HSLColor.fromAHSL(0.16, hue, 0.70, 0.58).toColor();
}

/// 这节课是否已上完：按该列当天日期 + 实际下课时刻判断，不能只看「今天」那一列。
bool courseIsPast(TtCourse c, String colISO) => TimetableStore.lessonPassed(
  colISO,
  TimetableStore.slotEnds[c.slotEnd.clamp(0, 10)],
);

/// 日程是否已结束：单次看它那一天，重复日程看这一列的日期；没写时刻不置灰。
bool eventIsPast(TtEvent e, String colISO) {
  final iso = e.isRepeating ? colISO : e.date;
  final d = DateTime.tryParse(iso);
  if (d == null) return false;
  final endMin = hm(e.end) >= 0 ? hm(e.end) : hm(e.start);
  if (endMin < 0) return false;
  final at = DateTime(d.year, d.month, d.day, endMin ~/ 60, endMin % 60);
  return at.isBefore(DateTime.now());
}

/// 这条日程是否和同一天的其他日程 / 课程在时间上真重叠。
bool eventOverlaps(TtEvent e, List<TtEvent> events, List<TtCourse> courses) {
  final sm = hm(e.start);
  final em = hm(e.end);
  if (sm < 0 || em < 0) return false;
  bool hit(int start, int end) => start < em && end > sm;
  for (final o in events) {
    if (identical(o, e)) continue;
    final os = hm(o.start);
    final oe = hm(o.end);
    if (os >= 0 && oe >= 0 && hit(os, oe)) return true;
  }
  for (final c in courses) {
    final cs = hm(TimetableStore.slotStarts[c.slotStart.clamp(0, 10)]);
    final ce = hm(TimetableStore.slotEnds[c.slotEnd.clamp(0, 10)]);
    if (hit(cs, ce)) return true;
  }
  return false;
}

/// 按与 [Text] 相同的样式 / 宽度 / 文字缩放量高度，供卡片决定放哪几行。
double measureTextHeight(
  BuildContext context,
  String text,
  TextStyle style, {
  required double maxWidth,
  int maxLines = 1,
  bool oneLine = false,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    maxLines: maxLines,
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: oneLine ? double.infinity : maxWidth);
  final h = tp.height;
  tp.dispose();
  return h;
}

/// 按与 [Text] 相同的样式量单行宽度（判断一行放不放得下）。
double measureTextWidth(BuildContext context, String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    maxLines: 1,
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}
