import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 上课提醒的排期算法是纯函数：给定课表 + 起始时间，算出「课前 15 分钟」的提醒时刻。
/// 这里只测算出来的时刻对不对（不触发插件 / 系统通知）。
void main() {
  // 2026-03-02 是周一
  const start = '2026-03-02';

  TtCourse course({
    String name = '高等数学',
    int day = 0,
    int slotStart = 0,
    int slotEnd = 1,
    String weekType = 'all',
    int weekStart = 1,
    int weekEnd = 20,
    String place = '教学楼A101',
  }) =>
      TtCourse(
        id: 'c-$name-$day-$slotStart',
        name: name,
        day: day,
        slotStart: slotStart,
        slotEnd: slotEnd,
        weekType: weekType,
        weekStart: weekStart,
        weekEnd: weekEnd,
        place: place,
      );

  TimetableStore storeWith(List<TtCourse> courses, {int weekCount = 20}) {
    final s = TimetableStore.instance;
    s.semesters = {
      '2025-12': SemesterTt(startDate: start, weekCount: weekCount, courses: courses),
    };
    return s;
  }

  group('节次与周次', () {
    test('11 节上课时刻与课表页一致', () {
      expect(ClassReminderService.classStartMinutes(course(slotStart: 0)), 8 * 60 + 20);
      expect(ClassReminderService.classStartMinutes(course(slotStart: 4)), 13 * 60);
      expect(ClassReminderService.classStartMinutes(course(slotStart: 8)), 18 * 60);
      expect(ClassReminderService.classStartMinutes(course(slotStart: 10)), 19 * 60 + 40);
    });

    test('周次范围与单双周', () {
      final c = course(weekStart: 3, weekEnd: 5);
      expect(ClassReminderService.meetsIn(c, 2), isFalse);
      expect(ClassReminderService.meetsIn(c, 3), isTrue);
      expect(ClassReminderService.meetsIn(c, 6), isFalse);

      final odd = course(weekType: 'odd');
      expect(ClassReminderService.meetsIn(odd, 1), isTrue);
      expect(ClassReminderService.meetsIn(odd, 2), isFalse);
      final even = course(weekType: 'even');
      expect(ClassReminderService.meetsIn(even, 2), isTrue);
      expect(ClassReminderService.meetsIn(even, 1), isFalse);
    });

    test('第一节课程的开始时刻 = 起始周周一 08:20', () {
      final at = ClassReminderService.classStart(start, 1, course());
      expect(at, DateTime(2026, 3, 2, 8, 20));
      // 第 2 周同一天
      expect(ClassReminderService.classStart(start, 2, course()), DateTime(2026, 3, 9, 8, 20));
      // 周三第 5 节（13:00）
      expect(ClassReminderService.classStart(start, 1, course(day: 2, slotStart: 4)),
          DateTime(2026, 3, 4, 13, 0));
    });
  });

  group('提醒排期', () {
    test('课前 15 分钟、按时间升序、只取未来窗口内的', () {
      // 站在第 2 周周一 08:00：08:05 的提醒还没到，该排；上周一（3/2）的已过，不排
      final from = DateTime(2026, 3, 9, 8, 0);
      final planned = ClassReminderService.plan(storeWith([course()]), from, horizonDays: 8);

      expect(planned.map((r) => r.at).toList(),
          [DateTime(2026, 3, 9, 8, 5), DateTime(2026, 3, 16, 8, 5)]);
      expect(planned.first.course.name, '高等数学');
    });

    test('多个学期 / 多节课合并排序，同一时刻不重复', () {
      // 窗口覆盖整个 3/2（周一）：上午高数、下午英语各一条；两学期里的「高数」算同一节
      final from = DateTime(2026, 2, 28);
      final s = TimetableStore.instance;
      s.semesters = {
        '2025-12': SemesterTt(startDate: start, weekCount: 20, courses: [
          course(name: '高数', day: 0, slotStart: 0),
          course(name: '英语', day: 0, slotStart: 4, place: 'B202'),
        ]),
        '2026-3': SemesterTt(startDate: start, weekCount: 20, courses: [
          // 同一节课在两个学期里都存在：只排一次
          course(name: '高数', day: 0, slotStart: 0),
        ]),
      };

      final planned = ClassReminderService.plan(s, from, horizonDays: 4);
      expect(planned.length, 2);
      expect(planned.first.at, DateTime(2026, 3, 2, 8, 5)); // 08:20 - 15min
      expect(planned.last.at, DateTime(2026, 3, 2, 12, 45)); // 13:00 - 15min
    });

    test('条数上限与时间窗口', () {
      final from = DateTime(2026, 3, 1);
      final planned = ClassReminderService.plan(storeWith([course()]), from, maxScheduled: 3);
      expect(planned.length, 3);
      for (var i = 1; i < planned.length; i++) {
        expect(planned[i].at.isAfter(planned[i - 1].at), isTrue);
      }

      final windowed = ClassReminderService.plan(storeWith([course()]), from, horizonDays: 6);
      expect(windowed.length, 1); // 只覆盖到 3/7（周一 3/2 一节）
    });

    test('起始日期缺失 / 空课程名不排期', () {
      final s = TimetableStore.instance;
      s.semesters = {'x': SemesterTt(startDate: '', weekCount: 20, courses: [course()])};
      expect(ClassReminderService.plan(s, DateTime(2026, 3, 1)), isEmpty);

      s.semesters = {
        'x': SemesterTt(startDate: start, weekCount: 20, courses: [course(name: '  ')]),
      };
      expect(ClassReminderService.plan(s, DateTime(2026, 3, 1)), isEmpty);
    });

    test('同一节课的通知 id 稳定（重排时覆盖同一条，不重复弹）', () {
      final from = DateTime(2026, 3, 1);
      final a = ClassReminderService.plan(storeWith([course()]), from).first;
      final b = ClassReminderService.plan(storeWith([course()]), from).first;
      expect(a.id, b.id);

      final other = ClassReminderService.plan(storeWith([course(name: '英语')]), from).first;
      expect(other.id, isNot(a.id));
    });
  });

  group('调休规则作用于提醒（与课表页渲染同规则）', () {
    TimetableStore storeWithAdjust(List<TtCourse> courses, List<TtAdjust> adj) {
      final s = TimetableStore.instance;
      s.semesters = {
        '2025-12': SemesterTt(
            startDate: start, weekCount: 20, courses: courses, adjustments: adj),
      };
      return s;
    }

    test('放假（off）那天不排提醒', () {
      // 2026-03-02 周一放假 → 该周周一的高数不提醒；3/9 正常上课照排
      final s = storeWithAdjust([course()], [TtAdjust(date: '2026-03-02', type: 'off')]);
      final planned = ClassReminderService.plan(s, DateTime(2026, 3, 1), horizonDays: 9);
      expect(planned.map((r) => r.at).toList(), [DateTime(2026, 3, 9, 8, 5)]);
    });

    test('按周 X 上课（follow）那天，提醒的是被借星期的课', () {
      // 3/2（周一）按周三的课表上课：应提醒周三的英语（13:00 前 15 分钟），而非周一自己的高数
      final s = storeWithAdjust(
        [course(), course(name: '英语', day: 2, slotStart: 4, place: 'B202')],
        [TtAdjust(date: '2026-03-02', type: 'follow', day: 2)],
      );
      final planned = ClassReminderService.plan(s, DateTime(2026, 3, 1), horizonDays: 2);
      expect(planned.length, 1);
      expect(planned.single.course.name, '英语');
      expect(planned.single.at, DateTime(2026, 3, 2, 12, 45));
    });

    test('effectiveDay：无规则按原列，off 为 null，follow 取被借的星期', () {
      final tt = SemesterTt(
        startDate: start,
        weekCount: 20,
        adjustments: [
          TtAdjust(date: '2026-03-04', type: 'off'), // 周三
          TtAdjust(date: '2026-03-05', type: 'follow', day: 0), // 周四按周一
        ],
      );
      expect(ClassReminderService.effectiveDay(tt, 1, 0), 0); // 周一无规则
      expect(ClassReminderService.effectiveDay(tt, 1, 2), isNull); // 周三放假
      expect(ClassReminderService.effectiveDay(tt, 1, 3), 0); // 周四按周一
    });
  });

  group('开关状态', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('默认关闭；关闭后持久化，重开 App 不会自己变回开启', () async {
      await ClassReminderService.I.loadEnabled();
      expect(ClassReminderService.I.enabled, isFalse, reason: '未设置过时默认关闭');

      // 模拟「关掉提醒」这一步（插件在测试环境不可用，排期失败不影响开关落盘）
      await ClassReminderService.I.disable();
      expect(ClassReminderService.I.enabled, isFalse);

      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool('class_reminder_on'), isFalse, reason: '关闭状态要落盘');

      // 下次启动：读回持久化值
      await ClassReminderService.I.loadEnabled();
      expect(ClassReminderService.I.enabled, isFalse);
    });

    test('持久化为开启时，启动读回开启状态', () async {
      SharedPreferences.setMockInitialValues({'class_reminder_on': true});
      await ClassReminderService.I.loadEnabled();
      expect(ClassReminderService.I.enabled, isTrue);
    });
  });

  group('排期打算（actionFor）', () {
    test('正常：清空后按当前课表重排', () {
      expect(
          ClassReminderService.actionFor(
              enabled: true, pluginEnabled: true, storeHasSemesters: true, planned: 5),
          ReminderAction.reschedule);
    });

    test('关掉提醒 / 插件被停用：只清空', () {
      expect(
          ClassReminderService.actionFor(
              enabled: false, pluginEnabled: true, storeHasSemesters: true, planned: 5),
          ReminderAction.clearOnly);
      expect(
          ClassReminderService.actionFor(
              enabled: true, pluginEnabled: false, storeHasSemesters: true, planned: 5),
          ReminderAction.clearOnly);
    });

    test('课表还没读出来：什么都不做（回归：原来会把用户已排好的提醒清掉，之后再也排不回来）', () {
      expect(
          ClassReminderService.actionFor(
              enabled: true, pluginEnabled: true, storeHasSemesters: false, planned: 0),
          ReminderAction.skip);
    });

    test('课表读出来了但一节课都没有：照样重排（把过期排期清掉）', () {
      expect(
          ClassReminderService.actionFor(
              enabled: true, pluginEnabled: true, storeHasSemesters: true, planned: 0),
          ReminderAction.reschedule);
    });
  });
}
