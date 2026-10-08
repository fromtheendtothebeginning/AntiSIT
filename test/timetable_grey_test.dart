import 'package:campus_service/timetable_store.dart';
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
}
