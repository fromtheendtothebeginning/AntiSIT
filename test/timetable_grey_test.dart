import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// 课表「已上过的课置灰」的判断：该列当天日期 + 实际下课时刻已过。
/// 这里锁住一个踩过的坑——colISO 是纯日期（yyyy-MM-dd），直接 parse 得到当天 00:00，
/// 如果拿它的时分去比下课时刻，会永远得出「还没下课」，整周都不置灰。
void main() {
  group('lessonPassed（已上过的课置灰）', () {
    test('同一列：下课时刻已过 → 灰', () {
      final now = DateTime(2026, 10, 8, 14, 0); // 周四 14:00
      expect(TimetableStore.lessonPassed('2026-10-08', '09:05', now: now), isTrue);
      expect(TimetableStore.lessonPassed('2026-10-08', '13:45', now: now), isTrue);
    });

    test('同一列：还没下课 → 不灰', () {
      final now = DateTime(2026, 10, 8, 14, 0);
      expect(TimetableStore.lessonPassed('2026-10-08', '14:35', now: now), isFalse);
      expect(TimetableStore.lessonPassed('2026-10-08', '15:40', now: now), isFalse);
    });

    test('本周早于今天的列同样置灰（周四看周一~周三）', () {
      final now = DateTime(2026, 10, 8, 8, 0); // 周四早上，今天第一节课还没上
      expect(TimetableStore.lessonPassed('2026-10-05', '09:05', now: now), isTrue, reason: '周一');
      expect(TimetableStore.lessonPassed('2026-10-06', '15:40', now: now), isTrue, reason: '周二');
      expect(TimetableStore.lessonPassed('2026-10-07', '20:25', now: now), isTrue, reason: '周三');
      expect(TimetableStore.lessonPassed('2026-10-08', '08:20' /* 未下课仍按 09:05 */, now: now),
          isFalse);
      expect(TimetableStore.lessonPassed('2026-10-09', '09:05', now: now), isFalse, reason: '周五未到');
    });

    test('未来的列不灰，过去的周次全灰', () {
      final now = DateTime(2026, 10, 8, 12, 0);
      expect(TimetableStore.lessonPassed('2026-10-12', '08:20', now: now), isFalse);
      expect(TimetableStore.lessonPassed('2026-09-28', '19:40', now: now), isTrue);
    });

    test('日期缺失 / 时刻异常 → 不灰（不抛异常）', () {
      expect(TimetableStore.lessonPassed('', '09:05'), isFalse);
      expect(TimetableStore.lessonPassed('2026-10-08', ''), isFalse);
      expect(TimetableStore.lessonPassed('2026-10-08', 'abc'), isFalse);
    });
  });

  group('upcomingOn（顶部「今天最近一节课」：上完就消失）', () {
    // 与课表页 _slotTimes/_slotEndTimes 同一份
    const endTimes = [
      '09:05', '09:55', '10:55', '11:45', '13:45', '14:35', '15:40', '16:30', '18:45', '19:35', '20:25',
    ];
    const start = '2026-03-02'; // 周一

    TtCourse at(int slotStart, int slotEnd, String name) => TtCourse(
          id: '$name-$slotStart',
          name: name,
          day: 0,
          slotStart: slotStart,
          slotEnd: slotEnd,
          weekType: 'all',
          weekStart: 1,
          weekEnd: 20,
          place: 'A101',
        );

    // 节次与下课时刻：第1节 09:05 / 第5节 13:45 / 第10节 19:35
    final all = [at(0, 0, '高数'), at(4, 5, '英语'), at(8, 9, '晚课')];

    test('早上：全部未上完，按时间升序，第一门是最近一节', () {
      final left = TimetableStore.upcomingOn(all,
          startDate: start, week: 1, dayIndex: 0, endTimes: endTimes,
          now: DateTime(2026, 3, 2, 7, 0));
      expect(left.map((c) => c.name).toList(), ['高数', '英语', '晚课']);
    });

    test('上午第一节课上完（09:05 后）→ 从列表里消失，最近一节变成英语', () {
      final left = TimetableStore.upcomingOn(all,
          startDate: start, week: 1, dayIndex: 0, endTimes: endTimes,
          now: DateTime(2026, 3, 2, 9, 30));
      expect(left.map((c) => c.name).toList(), ['英语', '晚课']);
    });

    test('正在上课的课仍算「还没上完」，留在列表里且排第一', () {
      // 09:00 时正在上第一节课（08:20-09:05）
      final during = TimetableStore.upcomingOn(all,
          startDate: start, week: 1, dayIndex: 0, endTimes: endTimes,
          now: DateTime(2026, 3, 2, 9, 0));
      expect(during.map((c) => c.name).toList(), ['高数', '英语', '晚课']);
      expect(during.first.name, '高数');
      // 09:10 第一节已下课 → 英语成为最近一节，且它还没开始（10:00 前后的间隙里也算未上完）
      final next = TimetableStore.upcomingOn(all,
          startDate: start, week: 1, dayIndex: 0, endTimes: endTimes,
          now: DateTime(2026, 3, 2, 9, 10));
      expect(next.first.name, '英语');
    });

    test('今天的课全上完 → 列表为空', () {
      final left = TimetableStore.upcomingOn(all,
          startDate: start, week: 1, dayIndex: 0, endTimes: endTimes,
          now: DateTime(2026, 3, 2, 21, 0));
      expect(left, isEmpty);
    });

    test('未设置学期起点：无从判断日期，原样返回', () {
      final left = TimetableStore.upcomingOn(all,
          startDate: '', week: 1, dayIndex: 0, endTimes: endTimes,
          now: DateTime(2026, 3, 2, 21, 0));
      expect(left.length, all.length);
    });
  });

  group('调休补课当天：「上完没有」按今天真实日期算，不按被借那天的日期', () {
    const endTimes = [
      '09:05', '09:55', '10:55', '11:45', '13:45', '14:35', '15:40', '16:30', '18:45', '19:35', '20:25',
    ];
    const start = '2026-03-02'; // 周一

    // 周三第 5 节（13:00-13:45）的一门课
    final wed = TtCourse(
      id: 'ds',
      name: '数据结构',
      day: 2,
      slotStart: 4,
      slotEnd: 4,
      weekType: 'all',
      weekStart: 1,
      weekEnd: 20,
      place: 'A101',
    );

    test('周六按周三的课表上课：周六 13:00 时这门课还没上完', () {
      final now = DateTime(2026, 3, 7, 13, 0); // 周六 = 第 1 周第 6 列（索引 5）
      // 正确姿势：日期用今天所在的列（索引 5 → 3/7）
      final ok = TimetableStore.upcomingOn([wed],
          startDate: start, week: 1, dayIndex: 5, endTimes: endTimes, now: now);
      expect(ok.map((c) => c.name).toList(), ['数据结构']);

      // 拿被借星期的日期（索引 2 → 3/4）去判，会被算成「3/4 的课早就下课了」→ 列表空
      // （顶部卡「不显示今天的课」就是这么来的）
      final wrong = TimetableStore.upcomingOn([wed],
          startDate: start, week: 1, dayIndex: 2, endTimes: endTimes, now: now);
      expect(wrong, isEmpty);
    });

    test('补课当天下课后仍照常消失', () {
      final after = TimetableStore.upcomingOn([wed],
          startDate: start, week: 1, dayIndex: 5, endTimes: endTimes,
          now: DateTime(2026, 3, 7, 14, 30));
      expect(after, isEmpty);
    });
  });
}
