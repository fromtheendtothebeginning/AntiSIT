import 'package:flutter/widgets.dart';

import 'package:campus_core/campus_core.dart';

/// 课程表里与 Widget 状态无关的纯布局/测量逻辑。
///
/// 从 [TimetablePage] 里拆出来：这些函数只依赖文本、颜色和时刻表，
/// 单测不需要搭整页手势/滚动环境，改排版时也更容易定位。

/// 与网站一致：课名哈希 → 5 色相（蓝紫 / 青绿 / 橙 / 绿 / 粉）。
const List<double> kCourseHues = [258.0, 174.0, 25.0, 145.0, 335.0];

Color courseColorFor(String name, {required bool dark}) {
  var h = 0;
  for (final ch in name.codeUnits) {
    h = (h * 31 + ch) % 100000;
  }
  final hue = kCourseHues[h % kCourseHues.length];
  // 深色下提亮提饱和，玻璃底上保持课块色彩辨识度（文字仍为 textPrimary）
  return dark
      ? HSLColor.fromAHSL(0.30, hue, 0.55, 0.68).toColor()
      : HSLColor.fromAHSL(0.16, hue, 0.70, 0.58).toColor();
}

/// 'HH:mm' → 当天分钟数；格式不对返回 -1。
int timeToMinutes(String s) {
  final p = s.split(':');
  if (p.length != 2) return -1;
  return (int.tryParse(p[0]) ?? -1) * 60 + (int.tryParse(p[1]) ?? -1);
}

/// 用和 [Text] 一样的样式、宽度和文字缩放来量高度：
/// 卡片据此决定放哪几行，量出来放不下就不放，避免靠 Clip 硬裁或文字叠字。
double textHeight(
  BuildContext context,
  String text,
  TextStyle style, {
  required double maxWidth,
  int maxLines = 1,
  bool oneLine = false,
}) {
  final tp = TextPainter(
    text: TextSpan(
        text: text, style: DefaultTextStyle.of(context).style.merge(style)),
    maxLines: maxLines,
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: oneLine ? double.infinity : maxWidth);
  final h = tp.height;
  tp.dispose();
  return h;
}

double textWidth(BuildContext context, String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(
        text: text, style: DefaultTextStyle.of(context).style.merge(style)),
    maxLines: 1,
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

/// 地点拆成「楼名 + 教室编号」：「第二教学楼 A301 多媒体教室」→（第二教学楼, A301）。
/// 单独的「3」多半是「3号楼」的楼号，不当教室号拆出来。
(String, String) splitPlace(String place) {
  final p = place.trim();
  if (p.isEmpty) return ('', '');
  final matches = RegExp(r'[A-Za-z]*\d[A-Za-z0-9-]*').allMatches(p).toList();
  if (matches.isEmpty) return (p, '');
  final m = matches.last;
  final code = m.group(0)!;
  if (code.length < 2 && !RegExp(r'[A-Za-z]').hasMatch(code)) return (p, '');
  final prefix = p
      .substring(0, m.start)
      .replaceAll(RegExp(r'[\s·,，、/|-]+$'), '')
      .trim();
  return (prefix, code);
}

/// 重叠的日程用不透明底色（先把玻璃卡面压到底色上）：
/// 半透明卡叠半透明卡时，下面那张的文字会透上来，看起来就是「重叠在一起」。
Color eventBackground({required bool isExam, required bool solid}) {
  final soft = isExam ? SemColors.dangerSoft : SemColors.accentSoft;
  if (!solid) return soft;
  final grid = Color.alphaBlend(SemColors.card, SemColors.bg);
  return Color.alphaBlend(soft, grid);
}

/// 这条日程是否和同一天的其他日程 / 课程在时间上真重叠。
bool eventOverlaps(TtEvent e, List<TtEvent> events, List<TtCourse> courses) {
  final sm = timeToMinutes(e.start);
  final em = timeToMinutes(e.end);
  if (sm < 0 || em < 0) return false;
  bool hit(int start, int end) => start < em && end > sm;
  for (final o in events) {
    if (identical(o, e)) continue;
    final os = timeToMinutes(o.start);
    final oe = timeToMinutes(o.end);
    if (os >= 0 && oe >= 0 && hit(os, oe)) return true;
  }
  for (final c in courses) {
    final cs = timeToMinutes(TimetableStore.slotStarts[c.slotStart.clamp(0, 10)]);
    final ce = timeToMinutes(TimetableStore.slotEnds[c.slotEnd.clamp(0, 10)]);
    if (hit(cs, ce)) return true;
  }
  return false;
}
