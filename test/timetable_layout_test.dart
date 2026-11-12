import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_timetable/timetable_layout.dart';

/// 课表纯布局逻辑（从 timetable_page 拆出来的部分）：不搭整页手势/滚动环境也能测。
void main() {
  test('timeToMinutes：正常 / 非法格式', () {
    expect(timeToMinutes('08:05'), 8 * 60 + 5);
    expect(timeToMinutes('23:59'), 23 * 60 + 59);
    expect(timeToMinutes(''), -1);
    expect(timeToMinutes('8点'), -1);
    expect(timeToMinutes('08:05:00'), -1);
  });

  test('splitPlace：楼名与教室号拆开', () {
    expect(splitPlace('第二教学楼 A301 多媒体教室'), ('第二教学楼', 'A301'));
    expect(splitPlace('24号楼1016'), ('24号楼', '1016'));
    expect(splitPlace('3'), ('3', ''), reason: '单独数字多半是楼号，不当教室号');
    expect(splitPlace(''), ('', ''));
  });

  test('courseColorFor：同名稳定、深色更亮更饱和', () {
    final light = courseColorFor('高等数学', dark: false);
    final again = courseColorFor('高等数学', dark: false);
    final dark = courseColorFor('高等数学', dark: true);
    expect(again, light);
    expect(dark, isNot(light));
    expect(HSLColor.fromColor(dark).lightness,
        greaterThan(HSLColor.fromColor(light).lightness));
  });

  test('eventOverlaps：与课程时段 / 其他日程重叠', () {
    final course = TtCourse(
      id: 'c1',
      name: '高数',
      day: 0,
      slotStart: 0,
      slotEnd: 0,
      weekType: 'all',
      weekStart: 1,
      weekEnd: 16,
    );
    final event = TtEvent(
      id: 'e1',
      name: '班会',
      date: '',
      start: TimetableStore.slotStarts.first,
      end: TimetableStore.slotEnds.first,
    );
    expect(eventOverlaps(event, [event], [course]), isTrue);
    expect(eventOverlaps(event, [event], []), isFalse, reason: '不和自己算重叠');

    final late = TtEvent(
      id: 'e2',
      name: '夜跑',
      date: '',
      start: '23:30',
      end: '23:50',
    );
    expect(eventOverlaps(late, [late], [course]), isFalse);
  });
}
