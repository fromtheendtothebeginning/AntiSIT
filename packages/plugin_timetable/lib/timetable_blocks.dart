import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'timetable_geometry.dart';

/// 周视图里的一节课块：按小节序号（0-10）定位，点击看详情。
Widget buildCourseBlock({
  required TtCourse course,
  required String colISO,
  required VoidCallback onTap,
}) {
  final past = courseIsPast(course, colISO) && AppState.I.dimCompleted;
  final rowStart = course.slotStart.clamp(0, 10);
  final rowEnd = course.slotEnd.clamp(0, 10) + 1; // 半开区间
  final top = weekRowY(rowStart);
  final height = (rowEnd - rowStart) * kSlotH - 4;
  final (placePrefix, placeCode) = _splitPlace(course.place);
  return Positioned(
    top: top + 2,
    height: height,
    left: 2,
    right: 2,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Opacity(
        // 上完的课整体压暗（与日视图卡片同一透明度）
        opacity: past ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: past ? SemColors.neutralSoft : courseBlockColor(course.name),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.15,
              child: LayoutBuilder(
                builder: (context, box) => _courseCardBody(
                  context,
                  box,
                  course,
                  past,
                  rowStart,
                  placePrefix,
                  placeCode,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 课程卡内容：按真实像素预算取舍，放不下就不放。
/// 优先级：课名（1-3 行）→ 教室号 → 上课时间 → 楼名 → 教师。
Widget _courseCardBody(
  BuildContext context,
  BoxConstraints box,
  TtCourse c,
  bool past,
  int rowStart,
  String placePrefix,
  String placeCode,
) {
  final w = box.maxWidth;
  final avail = box.maxHeight - 1; // 1px 余量，避免量高和实际排版差一点点就溢出
  final nameStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: past ? SemColors.textMuted : SemColors.textPrimary,
  );
  final timeStyle = TextStyle(
    fontSize: 9,
    color: past ? SemColors.textMuted : SemColors.textSecondary,
  );
  final placeStyle = TextStyle(
    fontSize: 10,
    height: 1.15,
    color: past ? SemColors.textMuted : SemColors.textSecondary,
  );
  final teacherStyle = TextStyle(fontSize: 9.5, color: SemColors.textMuted);

  double nameAt(int lines) =>
      measureTextHeight(context, c.name, nameStyle, maxWidth: w, maxLines: lines);
  final codeH = placeCode.isEmpty
      ? 0.0
      : measureTextHeight(
          context,
          placeCode,
          placeStyle,
          maxWidth: w,
          oneLine: true,
        );
  final prefixH1 = placePrefix.isEmpty
      ? 0.0
      : measureTextHeight(
          context,
          placePrefix,
          placeStyle,
          maxWidth: w,
          maxLines: 1,
        );
  // 课名先给 3 行；地点放不下就降到 2/1 行，课名永远至少留一行。
  final reserveH = placeCode.isNotEmpty ? codeH : prefixH1;
  var nameLines = 1;
  for (final n in const [3, 2, 1]) {
    if (nameAt(n) + reserveH <= avail) {
      nameLines = n;
      break;
    }
  }
  var used = nameAt(nameLines);

  var showCode = false;
  if (placeCode.isNotEmpty && used + codeH <= avail) {
    showCode = true;
    used += codeH;
  }
  // 地点排在时间前面：左侧节次轴已经写着上课时间，教室号比重复的时间更该保。
  var prefixLines = 0;
  if (placePrefix.isNotEmpty) {
    final h2 = measureTextHeight(
      context,
      placePrefix,
      placeStyle,
      maxWidth: w,
      maxLines: 2,
    );
    if (used + h2 <= avail) {
      prefixLines = 2;
      used += h2;
    } else if (used + prefixH1 <= avail) {
      prefixLines = 1;
      used += prefixH1;
    }
  }
  final timeText = TimetableStore.slotStarts[rowStart];
  final timeH = measureTextHeight(
    context,
    timeText,
    timeStyle,
    maxWidth: w,
    oneLine: true,
  );
  var showTime = false;
  if (used + timeH <= avail) {
    showTime = true;
    used += timeH;
  }
  final teacherH = c.teachers.isEmpty
      ? 0.0
      : measureTextHeight(
          context,
          c.teachers,
          teacherStyle,
          maxWidth: w,
          maxLines: 1,
        );
  var showTeacher = false;
  if (c.teachers.isNotEmpty && used + teacherH <= avail) {
    showTeacher = true;
    used += teacherH;
  }
  final pushDown =
      avail - used >= 6 && (showCode || prefixLines > 0 || showTeacher);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showTime)
        Text(
          timeText,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: timeStyle,
        ),
      Text(
        c.name,
        maxLines: nameLines,
        overflow: TextOverflow.ellipsis,
        style: nameStyle,
      ),
      if (pushDown) const Spacer(),
      if (prefixLines > 0)
        Text(
          placePrefix,
          maxLines: prefixLines,
          overflow: TextOverflow.ellipsis,
          style: placeStyle,
        ),
      if (showCode)
        Text(
          placeCode,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: placeStyle,
        ),
      if (showTeacher)
        Text(
          c.teachers,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: teacherStyle,
        ),
    ],
  );
}

/// 地点拆成「楼名 + 教室编号」：「第二教学楼 A301」→（第二教学楼, A301）。
/// 单独的「3」多半是「3号楼」的楼号，不当教室号拆出来。
(String, String) _splitPlace(String place) {
  final p = place.trim();
  if (p.isEmpty) return ('', '');
  final matches = RegExp(r'[A-Za-z]*\d[A-Za-z0-9-]*').allMatches(p).toList();
  if (matches.isEmpty) return (p, '');
  final m = matches.last;
  final code = m.group(0)!;
  if (code.length < 2 && !RegExp(r'[A-Za-z]').hasMatch(code)) return (p, '');
  final prefix =
      p.substring(0, m.start).replaceAll(RegExp(r'[\s·,，、/|-]+$'), '').trim();
  return (prefix, code);
}

/// 日程 / 考试块：按真实时刻定位，不吸附到整节（首尾相接的日程不会叠在一起）。
List<Widget> buildEventBlocks({
  required TtEvent event,
  required String colISO,
  required bool solid,
  required VoidCallback onTap,
}) {
  final sm = hm(event.start);
  final em = hm(event.end);
  if (sm < 0 || em < 0) return const [];
  var first = -1;
  for (var s = 0; s <= 10; s++) {
    final bMin = hm(TimetableStore.slotStarts[s]);
    final eMin = hm(TimetableStore.slotEnds[s]);
    if (em > bMin && sm < eMin && first < 0) first = s;
  }
  final isExam = event.kind == 'exam';
  if (first < 0) {
    // 16:30–18:00 没有节次：落在晚饭空档里的日程单独画在空档行，别让它保存了却看不见。
    final gapStart = hm(TimetableStore.slotEnds[7]);
    final gapEnd = hm(TimetableStore.slotStarts[8]);
    if (em <= gapStart || sm >= gapEnd) return const [];
    final gapTop = kBandH + 4 * kSlotH + kNoonH + kBandH + 4 * kSlotH;
    return [
      Positioned(
        top: gapTop + 2,
        height: kGapH - 4,
        left: 2,
        right: 2,
        child: GestureDetector(
          onTap: onTap,
          child: Opacity(
            opacity:
                eventIsPast(event, colISO) && AppState.I.dimCompleted ? 0.55 : 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: _eventBg(isExam, solid),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (isExam ? SemColors.danger : SemColors.accent)
                      .withValues(alpha: 0.4),
                ),
              ),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.15,
                child: LayoutBuilder(
                  builder: (context, box) =>
                      _eventCardBody(context, box, event, isExam, compact: true),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
  final gridTop = hm(TimetableStore.slotStarts.first);
  final gridBottom = hm(TimetableStore.slotEnds.last);
  final from = math.max(sm, gridTop);
  final to = math.min(em, gridBottom);
  final top = _yOfMinute(from);
  var bottom = _yOfMinute(to);
  // 太短的日程给一个能放下一行字的可见高度（不吸附回整节，避免又和邻居叠上）
  if (bottom - top < 26) bottom = math.min(top + 26, weekGridHeight);
  return [
    Positioned(
      top: top + 2,
      height: math.max(bottom - top - 4, 8),
      left: 2,
      right: 2,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          // 时间过了的日程跟课一样压暗（0.55，与课程块 / 日视图卡片一致）
          opacity:
              eventIsPast(event, colISO) && AppState.I.dimCompleted ? 0.55 : 1,
          child: Container(
            padding: const EdgeInsets.all(3),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _eventBg(isExam, solid),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (isExam ? SemColors.danger : SemColors.accent)
                    .withValues(alpha: 0.4),
              ),
            ),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.15,
              child: LayoutBuilder(
                builder: (context, box) =>
                    _eventCardBody(context, box, event, isExam),
              ),
            ),
          ),
        ),
      ),
    ),
  ];
}

/// 一天中的分钟 → 网格 y：节次内按分钟线性插值，午休 / 晚饭空档按空档高度插值。
double _yOfMinute(int minute) {
  for (var s = 0; s <= 10; s++) {
    final st = hm(TimetableStore.slotStarts[s]);
    final en = hm(TimetableStore.slotEnds[s]);
    if (minute <= st) return weekRowY(s);
    if (minute <= en) return weekRowY(s) + (minute - st) / (en - st) * kSlotH;
    if (s < 10) {
      final nextSt = hm(TimetableStore.slotStarts[s + 1]);
      if (minute < nextSt) {
        final segTop = weekRowY(s) + kSlotH;
        final segBottom = weekRowY(s + 1);
        return segTop + (minute - en) / (nextSt - en) * (segBottom - segTop);
      }
    }
  }
  return weekRowY(10) + kSlotH;
}

/// 日程卡内容：课名优先，其次时间，再放地点 / 座位；每行按真实像素量过，放不下就不放。
Widget _eventCardBody(
  BuildContext context,
  BoxConstraints box,
  TtEvent e,
  bool isExam, {
  bool compact = false,
}) {
  final w = box.maxWidth;
  final avail = box.maxHeight - 1;
  final nameStyle = TextStyle(
    fontSize: compact ? 9.5 : 10.5,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: isExam ? SemColors.danger : SemColors.textPrimary,
  );
  final timeStyle = TextStyle(
    fontSize: compact ? 8 : 9,
    color: isExam ? SemColors.danger : SemColors.accent,
  );
  final placeStyle = TextStyle(
    fontSize: compact ? 9 : 9.5,
    color: SemColors.textSecondary,
  );
  final seatStyle = TextStyle(fontSize: 9, color: SemColors.textSecondary);
  final (placePrefix, placeCode) = _splitPlace(e.place);

  double nameAt(int lines) =>
      measureTextHeight(context, e.name, nameStyle, maxWidth: w, maxLines: lines);
  if (nameAt(1) > avail) return const SizedBox.shrink();

  // 时间先压成一行；窄列放不下完整区间就只留开始时刻，别折成两行把卡片撑爆。
  var timeText = '${e.start}${e.end.isNotEmpty ? '~${e.end}' : ''}';
  if (e.end.isNotEmpty && measureTextWidth(context, timeText, timeStyle) > w) {
    timeText = e.start;
  }
  final timeH = timeText.isEmpty
      ? 0.0
      : measureTextHeight(context, timeText, timeStyle,
          maxWidth: w, oneLine: true);

  // 课名尽量多留行；为了塞时间可以把 3 行降到 2 行，但不降到 1 行——课名比时间更重要。
  var nameLines = 1;
  for (final n in const [3, 2, 1]) {
    if (nameAt(n) <= avail) {
      nameLines = n;
      break;
    }
  }
  var used = nameAt(nameLines);
  var showTime = false;
  if (timeH > 0 && used + timeH <= avail) {
    showTime = true;
    used += timeH;
  } else if (nameLines > 2 && nameAt(2) + timeH <= avail) {
    nameLines = 2;
    used = nameAt(2) + timeH;
    showTime = true;
  }

  final codeH = placeCode.isEmpty
      ? 0.0
      : measureTextHeight(
          context,
          placeCode,
          placeStyle,
          maxWidth: w,
          oneLine: true,
        );
  var showCode = false;
  if (placeCode.isNotEmpty && used + codeH <= avail) {
    showCode = true;
    used += codeH;
  }
  var prefixLines = 0;
  if (placePrefix.isNotEmpty) {
    final h2 = measureTextHeight(
      context,
      placePrefix,
      placeStyle,
      maxWidth: w,
      maxLines: 2,
    );
    final h1 = measureTextHeight(
      context,
      placePrefix,
      placeStyle,
      maxWidth: w,
      maxLines: 1,
    );
    if (used + h2 <= avail) {
      prefixLines = 2;
      used += h2;
    } else if (used + h1 <= avail) {
      prefixLines = 1;
      used += h1;
    }
  }
  final seatH = e.seat.isEmpty
      ? 0.0
      : measureTextHeight(
          context,
          '座位 ${e.seat}',
          seatStyle,
          maxWidth: w,
          maxLines: 1,
          oneLine: true,
        );
  var showSeat = false;
  if (e.seat.isNotEmpty && used + seatH <= avail) {
    showSeat = true;
    used += seatH;
  }
  final pushDown = !compact &&
      avail - used >= 6 &&
      (showCode || prefixLines > 0 || showSeat);

  return Column(
    mainAxisAlignment:
        compact ? MainAxisAlignment.center : MainAxisAlignment.start,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showTime)
        Text(
          timeText,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: timeStyle,
        ),
      Text(
        e.name,
        maxLines: nameLines,
        overflow: TextOverflow.ellipsis,
        style: nameStyle,
      ),
      if (pushDown) const Spacer(),
      if (prefixLines > 0)
        Text(
          placePrefix,
          maxLines: prefixLines,
          overflow: TextOverflow.ellipsis,
          style: placeStyle,
        ),
      if (showCode)
        Text(
          placeCode,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: placeStyle,
        ),
      if (showSeat)
        Text(
          '座位 ${e.seat}',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: seatStyle,
        ),
    ],
  );
}

/// 重叠的日程改用不透明底色：半透明卡叠半透明卡会让下面的文字透上来。
Color _eventBg(bool isExam, bool solid) {
  final soft = isExam ? SemColors.dangerSoft : SemColors.accentSoft;
  if (!solid) return soft;
  final grid = Color.alphaBlend(SemColors.card, SemColors.bg);
  return Color.alphaBlend(soft, grid);
}
