import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'timetable_geometry.dart';

/// 课程详情弹层：时间 / 地点 / 教师 / 代码 / 教学班，带编辑与删除入口。
void showCourseDetailSheet(
  BuildContext context, {
  required TtCourse course,
  required bool imported,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    course.name,
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                ),
                if (imported) Capsule('教务课程', color: SemColors.info),
              ],
            ),
            const SizedBox(height: 12),
            _detailRow(
              '时间',
              '周${'一二三四五六日'[course.day]} 第${course.slotStart + 1}-${course.slotEnd + 1}节 · '
                  '${weekTypeLabel(course.weekType)} ${course.weekStart}-${course.weekEnd} 周',
            ),
            _detailRow('地点', course.place.isEmpty ? '-' : course.place),
            _detailRow('教师', course.teachers.isEmpty ? '-' : course.teachers),
            if (course.code.isNotEmpty) _detailRow('课程代码', course.code),
            if (course.clazz.isNotEmpty) _detailRow('教学班', course.clazz),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onEdit();
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(imported ? '编辑（转手动）' : '编辑'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onDelete();
                  },
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: SemColors.danger,
                  ),
                  label: Text('删除', style: TextStyle(color: SemColors.danger)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 删除课程：选择「仅本周一次」还是「全部」；手动课程按周次拆分保留其余周。
Future<void> deleteCourse(
  BuildContext context, {
  required SemesterTt tt,
  required TtCourse course,
  required int week,
  required bool imported,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('删除方式', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            title: Text('仅第 $week 周这一次'),
            subtitle: imported
                ? null
                : const Text('自动拆分周次，其余周保留', style: TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(ctx, 'week'),
          ),
          ListTile(
            title: Text(imported ? '所有周的该课程' : '全部场次（同名课程）'),
            onTap: () => Navigator.pop(ctx, 'all'),
          ),
        ],
      ),
    ),
  );
  if (choice == null) return;
  if (choice == 'week') {
    if (imported) {
      TimetableStore.removeImportedOccurrence(
        tt,
        course,
        all: false,
        week: week,
      );
    } else {
      // 拆分周次：原条目替换成前段 + 后段
      final parts = <TtCourse>[];
      if (course.weekStart < week) {
        parts.add(
          TtCourse(
            id: TimetableStore.genId(),
            name: course.name,
            place: course.place,
            teachers: course.teachers,
            day: course.day,
            slotStart: course.slotStart,
            slotEnd: course.slotEnd,
            weekType: course.weekType,
            weekStart: course.weekStart,
            weekEnd: week - 1,
          ),
        );
      }
      if (week < course.weekEnd) {
        parts.add(
          TtCourse(
            id: TimetableStore.genId(),
            name: course.name,
            place: course.place,
            teachers: course.teachers,
            day: course.day,
            slotStart: course.slotStart,
            slotEnd: course.slotEnd,
            weekType: course.weekType,
            weekStart: week + 1,
            weekEnd: course.weekEnd,
          ),
        );
      }
      tt.courses.removeWhere((x) => x.id == course.id);
      tt.courses.addAll(parts);
    }
  } else {
    if (imported) {
      TimetableStore.removeImportedOccurrence(tt, course, all: true);
    } else {
      tt.courses.removeWhere((x) => x.name == course.name);
    }
  }
  await TimetableStore.instance.save();
}

/// 日程详情弹层：时间 / 地点 / 座位 / 备注，带编辑与删除入口。
void showEventDetailSheet(
  BuildContext context, {
  required TtEvent event,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    event.name,
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                ),
                if (event.kind == 'exam')
                  Capsule('考试', color: SemColors.danger),
                if (event.isRepeating)
                  Capsule(event.repeatLabel, color: SemColors.info),
              ],
            ),
            const SizedBox(height: 12),
            _detailRow('时间', eventTimeText(event)),
            if (event.isRepeating) _detailRow('循环', eventRepeatText(event)),
            if (event.place.isNotEmpty) _detailRow('地点', event.place),
            if (event.seat.isNotEmpty) _detailRow('座位', event.seat),
            if (event.note.isNotEmpty) _detailRow('备注', event.note),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onEdit();
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('编辑'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onDelete();
                  },
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: SemColors.danger,
                  ),
                  label: Text('删除', style: TextStyle(color: SemColors.danger)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 日程详情里的「时间」一行：单次写日期，重复写「每周周X / 每月 N 号」+ 起止时刻。
String eventTimeText(TtEvent e) {
  final wd = '周${'一二三四五六日'[e.day.clamp(0, 6)]}';
  final span = e.start.isEmpty
      ? ''
      : '${e.start}${e.end.isEmpty ? '' : '~${e.end}'}';
  final when = !e.isRepeating
      ? e.date
      : switch (e.repeat) {
          TtEvent.repeatMonthly => '每月 ${_eventMonthDay(e)} 号',
          _ => '${e.repeatLabel} $wd',
        };
  return [when, if (span.isNotEmpty) span].join(' ');
}

/// 日程详情里的「循环」一行：重复类型 + 起止日期（空串换成不限 / 学期末）。
String eventRepeatText(TtEvent e) {
  final label = e.repeatLabel;
  final from = e.repeatStart;
  final to = e.repeatEnd;
  if (from.isEmpty && to.isEmpty) return '$label · 不限起止';
  return '$label · ${from.isEmpty ? '不限' : from} ~ ${to.isEmpty ? '学期末' : to}';
}

/// 每月重复的「几号」：取 repeatStart 的日；没有起点时按每月 1 号（默认）。
String _eventMonthDay(TtEvent e) {
  final d = DateTime.tryParse(e.repeatStart);
  return '${d?.day ?? 1}';
}

/// 详情弹层里的一行「标签 : 值」。
Widget _detailRow(String k, String v) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 72,
        child: Text(k, style: TextStyle(color: SemColors.textSecondary)),
      ),
      Expanded(child: Text(v)),
    ],
  ),
);
