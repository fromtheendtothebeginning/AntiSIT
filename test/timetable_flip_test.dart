import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_timetable/plugin_timetable.dart';

/// 需求：下课立刻变灰——按下课时刻排一次性定时器，这里测那个「下一次到点时刻」的算法。
void main() {
  // 与页面里 _slotEndTimes 一致的节次下课时刻
  const ends = <String>[
    '09:05', '09:55', '11:00', '11:50', '13:45',
    '14:35', '15:40', '16:30', '18:45', '19:35', '20:25',
  ];

  group('下课到点时刻', () {
    test('取今天最近的下课时刻', () {
      expect(TimetablePage.nextSlotEndAfter(DateTime(2026, 10, 9, 9, 54), ends),
          DateTime(2026, 10, 9, 9, 55));
      expect(TimetablePage.nextSlotEndAfter(DateTime(2026, 10, 9, 9, 50), ends),
          DateTime(2026, 10, 9, 9, 55));
    });

    test('正好在下课那一刻：已经不算「下一个」，轮到再下一节', () {
      expect(TimetablePage.nextSlotEndAfter(DateTime(2026, 10, 9, 9, 55), ends),
          DateTime(2026, 10, 9, 11, 0));
    });

    test('下课刚过 1 秒：同样轮到下一节（这一刻已经重绘过了）', () {
      expect(TimetablePage.nextSlotEndAfter(DateTime(2026, 10, 9, 9, 55, 1), ends),
          DateTime(2026, 10, 9, 11, 0));
    });

    test('跨过午休与晚上的节次也连续', () {
      expect(TimetablePage.nextSlotEndAfter(DateTime(2026, 10, 9, 11, 50), ends),
          DateTime(2026, 10, 9, 13, 45));
      expect(TimetablePage.nextSlotEndAfter(DateTime(2026, 10, 9, 19, 30), ends),
          DateTime(2026, 10, 9, 19, 35));
    });

    test('今天课都结束了就没有下一个到点（交给 60s 心跳兜跨天）', () {
      expect(TimetablePage.nextSlotEndAfter(DateTime(2026, 10, 9, 20, 25), ends), isNull);
      expect(TimetablePage.nextSlotEndAfter(DateTime(2026, 10, 9, 23, 59), ends), isNull);
    });

    test('到点时刻总能跨到「下课那一秒之后」，所以定时器只需再加 1 秒', () {
      final now = DateTime(2026, 10, 9, 9, 54, 5);
      final next = TimetablePage.nextSlotEndAfter(now, ends)!;
      expect(next.difference(now), const Duration(seconds: 55));
      expect(next.difference(now) + const Duration(seconds: 1),
          const Duration(seconds: 56));
    });
  });
}
