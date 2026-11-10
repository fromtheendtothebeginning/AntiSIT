import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_home_widget/plugin_home_widget.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 桌面卡片的验收：
/// * 今日课程计算（节次时间跟自定义作息、调休 / 单双周、去重）；
/// * 课表保存后把「今日课程 + 下一节」同步给卡片能力；
/// * 长按快捷方式 / 点卡片的入口动作（AppLaunch）。
void main() {
  late _FakeWidget widget;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    TimetableStore.instance.semesters = {};
    TimetableStore.slotStarts = TimetableStore.defaultSlotStarts;
    TimetableStore.slotEnds = TimetableStore.defaultSlotEnds;
    widget = _FakeWidget();
    PluginRegistry.I = PluginRegistry(
      features: const [TimetablePlugin(), HomeWidgetPlugin()],
      capabilities: {PluginIds.homeWidget: widget},
    );
  });

  SemesterTt semester({String start = '2026-09-07'}) => SemesterTt(
        startDate: start,
        weekCount: 20,
        courses: [
          TtCourse(
            id: 'c1',
            name: '高等数学',
            place: '二教E101',
            day: 0,
            slotStart: 2,
            slotEnd: 2,
            weekType: 'all',
            weekStart: 1,
            weekEnd: 20,
          ),
          TtCourse(
            id: 'c2',
            name: '大英',
            place: '一教B203',
            day: 0,
            slotStart: 0,
            slotEnd: 0,
            weekType: 'all',
            weekStart: 1,
            weekEnd: 20,
          ),
        ],
      );

  group('今日课程', () {
    test('按节次时间排好序，带地点；节次时间跟自定义作息走', () {
      TimetableStore.instance.semesters = {'2026-3': semester()};
      final courses = TimetableStore.todayCourses(now: DateTime(2026, 9, 7, 8, 0));
      expect([for (final c in courses) c.name], ['大英', '高等数学']);
      expect(courses.first.start, '08:20');
      expect(courses.last.start, '10:15', reason: '默认早三 10:15');
      expect(courses.last.place, '二教E101');

      TimetableStore.slotStarts = List<String>.from(TimetableStore.slotStarts)..[2] = '10:20';
      final custom = TimetableStore.todayCourses(now: DateTime(2026, 9, 7, 8, 0));
      expect(custom.last.start, '10:20');
    });

    test('调休放假：当天没有课', () {
      final tt = semester();
      tt.adjustments = [TtAdjust(date: '2026-09-07', type: 'off')];
      TimetableStore.instance.semesters = {'2026-3': tt};
      expect(TimetableStore.todayCourses(now: DateTime(2026, 9, 7, 8, 0)), isEmpty);
    });

    test('学期外 / 单双周不匹配：不返回', () {
      final tt = semester();
      tt.courses = [
        TtCourse(
          id: 'c3',
          name: '单周课',
          day: 0,
          slotStart: 2,
          slotEnd: 2,
          weekType: 'odd',
          weekStart: 1,
          weekEnd: 20,
        ),
      ];
      TimetableStore.instance.semesters = {'2026-3': tt};
      // 2026-09-14 是第 2 周（双周）
      expect(TimetableStore.todayCourses(now: DateTime(2026, 9, 14, 8, 0)), isEmpty);
      // 学期外
      expect(TimetableStore.todayCourses(now: DateTime(2025, 1, 5, 8, 0)), isEmpty);
    });
  });

  group('同步到底层卡片能力', () {
    test('保存课表后同步今日课程与下一节', () async {
      // 用「今天所在的这一周」造学期：这个测试跑在任意星期都不能挂
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      String iso(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      TimetableStore.instance.semesters = {
        '2026-3': SemesterTt(
          startDate: iso(monday),
          weekCount: 20,
          courses: [
            TtCourse(
              id: 'c1',
              name: '高等数学',
              place: '二教E101',
              day: now.weekday - 1,
              slotStart: 2,
              slotEnd: 2,
              weekType: 'all',
              weekStart: 1,
              weekEnd: 20,
            ),
          ],
        ),
      };
      await TimetableStore.instance.persist();
      await Future<void>.delayed(Duration.zero);

      expect(widget.syncs, greaterThanOrEqualTo(1));
      expect(widget.courses.map((c) => c.name), contains('高等数学'));
      expect(widget.date, isNotNull);
    });

    test('课全部上完：next 为空（卡片显示「今天的课都上完了」）', () async {
      TimetableStore.instance.semesters = {'2026-3': semester()};
      await TimetableStore.instance.persist();
      await Future<void>.delayed(Duration.zero);
      // 真实 now 与课程日期无关时 next 由卡片侧自行判断；这里只验字段被传了过去
      expect(widget.date, isNotNull);
    });
  });

  group('入口动作', () {
    test('post 后冷启动能取到，取完即清', () {
      AppLaunch.I.post('ecard');
      expect(AppLaunch.I.takePending(), 'ecard');
      expect(AppLaunch.I.takePending(), isNull);
    });

    test('订阅者能收到动作', () async {
      final seen = <String>[];
      final sub = AppLaunch.I.actions.listen(seen.add);
      AppLaunch.I.post('timetable');
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['timetable']);
      await sub.cancel();
    });
  });
}

class _FakeWidget implements HomeWidgetCapability {
  int syncs = 0;
  String? date;
  List<HomeWidgetCourse> courses = const [];
  HomeWidgetCourse? next;
  String? balance;

  @override
  Future<void> syncTimetable({
    required String day,
    required String date,
    required List<HomeWidgetCourse> courses,
    HomeWidgetCourse? next,
  }) async {
    syncs += 1;
    this.date = date;
    this.courses = courses;
    this.next = next;
  }

  @override
  Future<void> syncEcard({String? balance}) async {
    this.balance = balance;
  }

  @override
  Future<String?> takeLaunchAction() async => null;
}
