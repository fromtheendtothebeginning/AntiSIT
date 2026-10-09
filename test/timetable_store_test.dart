import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_core/campus_core.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TimetableStore.instance.semesters = {};
  });

  group('locateToday / 学期推算', () {
    test('locateToday 返回当前周，学期外/空起点返回 null', () {
      // 2026-09-07 是周一；只要测试日仍在该学期 20 周内就应返回 1..20
      expect(TimetableStore.locateToday('2026-09-07', 20), inInclusiveRange(1, 20));
      expect(TimetableStore.locateToday('', 20), isNull);
      expect(TimetableStore.locateToday('2099-09-07', 20), isNull); // 未开学
      expect(TimetableStore.locateToday('2020-09-07', 20), isNull); // 已结束
    });

    test('semesterKeyOf 按月份归学期', () {
      expect(TimetableStore.semesterKeyOf(DateTime(2026, 9, 1)), '2026-3');
      expect(TimetableStore.semesterKeyOf(DateTime(2026, 12, 20)), '2026-3');
      expect(TimetableStore.semesterKeyOf(DateTime(2026, 1, 10)), '2025-3');
      expect(TimetableStore.semesterKeyOf(DateTime(2026, 3, 1)), '2025-12');
      expect(TimetableStore.semesterKeyOf(DateTime(2026, 7, 1)), '2025-16');
    });

    test('dateOfWeekDay 第 2 周周三 = 起点 + 9 天', () {
      final d = TimetableStore.dateOfWeekDay('2026-09-07', 2, 2);
      expect(TimetableStore.iso(d), '2026-09-16');
    });
  });

  group('deriveImported（周次切段）', () {
    TtCourse occ(int day, {String name = '数学', int slotStart = 0, int slotEnd = 1}) =>
        TtCourse(id: '', name: name, place: '二教E101', teachers: '王', day: day, slotStart: slotStart, slotEnd: slotEnd, weekType: 'all', weekStart: 1, weekEnd: 1);

    test('连续周合并为 all，跳周同奇偶合并为 odd/even', () {
      final tt = SemesterTt();
      tt.jwxtWeeks = {
        '1': [occ(0)], '2': [occ(0)], '3': [occ(0)],
        '6': [occ(1, name: '英语')], '8': [occ(1, name: '英语')],
        '5': [occ(2, name: '物理')], '7': [occ(2, name: '物理')], '9': [occ(2, name: '物理')],
      };
      final courses = TimetableStore.deriveImported(tt);
      final math = courses.firstWhere((c) => c.name == '数学');
      expect(math.weekType, 'all');
      expect(math.weekStart, 1);
      expect(math.weekEnd, 3);
      final eng = courses.firstWhere((c) => c.name == '英语');
      expect(eng.weekType, 'even');
      expect(eng.weekStart, 6);
      expect(eng.weekEnd, 8);
      final phy = courses.firstWhere((c) => c.name == '物理');
      expect(phy.weekType, 'odd');
      expect(phy.weekStart, 5);
      expect(phy.weekEnd, 9);
    });

    test('coversWeek 按 weekType 过滤', () {
      final c = TtCourse(id: 'a', name: 'x', day: 0, slotStart: 0, slotEnd: 1, weekType: 'odd', weekStart: 1, weekEnd: 9);
      expect(TimetableStore.coversWeek(c, 3), isTrue);
      expect(TimetableStore.coversWeek(c, 4), isFalse);
      expect(TimetableStore.coversWeek(c, 10), isFalse); // 超出范围
    });
  });

  group('调休与考试', () {
    test('mergeAdjustments 同日期覆盖并升序', () {
      final prev = [TtAdjust(date: '2026-10-02', type: 'off'), TtAdjust(date: '2026-10-01', type: 'off')];
      final merged = TimetableStore.mergeAdjustments(prev, [TtAdjust(date: '2026-10-02', type: 'follow', day: 0)]);
      expect(merged.map((a) => a.date).toList(), ['2026-10-01', '2026-10-02']);
      expect(merged[1].type, 'follow');
    });

    test('expandDateRange 含两端且上限 42 天', () {
      final days = TimetableStore.expandDateRange('2026-10-01', '2026-10-03');
      expect(days.length, 3);
      expect(TimetableStore.expandDateRange('2026-10-01', null).length, 1);
      expect(TimetableStore.expandDateRange('2026-01-01', '2027-01-01').length, 42);
    });

    test('addExamEvents 转日程、去重、范围过滤', () {
      final tt = SemesterTt()
        ..startDate = '2026-09-07'
        ..weekCount = 4; // 学期到 2026-10-04 为止
      final exams = [
        {'name': '高数', 'date': '2026-09-20', 'start': '08:00', 'end': '09:40', 'place': '二教E101', 'seat': '12', 'ksmc': '期末考试'},
        {'name': '高数', 'date': '2026-09-20', 'start': '08:00', 'end': '09:40'}, // 重复
        {'name': '英语', 'date': '2026-12-20', 'start': '08:00', 'end': '09:40'}, // 范围外
      ];
      expect(TimetableStore.addExamEvents(tt, exams), 1);
      expect(tt.events.length, 1);
      expect(tt.events.first.kind, 'exam');
      expect(tt.events.first.note, '期末考试 · 座位 12');
    });
  });

  group('新建学期', () {
    test('建档 → persist → load 往返后学期仍在（切换学期的基础）', () async {
      final store = TimetableStore.instance;
      store.semester('2026', '12'); // 建空学期（页面新建学期同款路径）
      store.semesters['2026-12']!.startDate = '2027-03-01';
      await store.persist();

      store.semesters = {}; // 模拟重启后从磁盘加载
      await store.load();
      expect(store.semesters.containsKey('2026-12'), isTrue);
      expect(store.semesters['2026-12']!.startDate, '2027-03-01');
    });

    test('semester() 幂等：重复访问同一学期不重建', () {
      final store = TimetableStore.instance;
      final a = store.semester('2025', '3');
      a.startDate = '2025-09-01';
      final b = store.semester('2025', '3');
      expect(identical(a, b), isTrue);
      expect(b.startDate, '2025-09-01');
    });
  });

  group('删除教务课程', () {
    test('removeImportedOccurrence 仅删指定周', () {
      final tt = SemesterTt();
      tt.jwxtWeeks = {
        '1': [TtCourse(id: '', name: '数学', day: 0, slotStart: 0, slotEnd: 1, weekType: 'all', weekStart: 1, weekEnd: 1)],
        '2': [TtCourse(id: '', name: '数学', day: 0, slotStart: 0, slotEnd: 1, weekType: 'all', weekStart: 1, weekEnd: 1)],
      };
      TimetableStore.removeImportedOccurrence(tt, tt.jwxtWeeks['1']!.first, all: false, week: 1);
      expect(tt.jwxtWeeks.containsKey('1'), isFalse);
      expect(tt.jwxtWeeks['2'], isNotEmpty);
    });
  });
}
