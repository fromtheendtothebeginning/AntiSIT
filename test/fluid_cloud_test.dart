import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_course_cloud/plugin_course_cloud.dart';
import 'package:plugin_fluid_cloud/plugin_fluid_cloud.dart';
import 'package:plugin_reminder/plugin_reminder.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「流体云课程通知」的验收：
/// * 流体云插件的能力接口 / 课程窗口计算（节次时间跟自定义作息走）；
/// * 课程通知三选一（不通知 / 弹窗 / 流体云）落盘并真的切换排期；
/// * 上课提醒在非弹窗模式下不再排课程提醒（避免和流体云重复）。
void main() {
  late _FakeCloud fake;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    await AppState.I.setCourseNotifyMode('popup');
    TimetableStore.instance.semesters = {};
    TimetableStore.slotStarts = TimetableStore.defaultSlotStarts;
    TimetableStore.slotEnds = TimetableStore.defaultSlotEnds;
    fake = _FakeCloud();
    PluginRegistry.I = PluginRegistry(
      features: const [TimetablePlugin(), FluidCloudPlugin(), CourseCloudPlugin()],
      capabilities: {PluginIds.fluidCloud: fake},
    );
    // 课程通知插件默认关闭：开启后才在课程表设置里出现「课程通知方式」
    await PluginRegistry.I.enable(PluginIds.courseCloud);
  });

  SemesterTt semesterWithCourse() => SemesterTt(
        startDate: '2026-09-07', // 周一
        weekCount: 20,
        courses: [
          TtCourse(
            id: 'c1',
            name: '高等数学',
            place: '二教E101',
            day: 0,
            slotStart: 2, // 默认 10:15 上课
            slotEnd: 2, // 10:55 下课
            weekType: 'all',
            weekStart: 1,
            weekEnd: 20,
          ),
        ],
      );

  group('课程窗口', () {
    test('按节次时间算出亮起 / 收起时刻，标题与地点带上', () {
      TimetableStore.instance.semesters = {'2026-3': semesterWithCourse()};
      final now = DateTime(2026, 9, 7, 9, 0);
      final windows = CourseCloudService.planWindows(TimetableStore.instance, now);

      expect(windows, isNotEmpty);
      final w = windows.first;
      expect(w.title, '高等数学');
      expect(w.startAt, DateTime(2026, 9, 7, 10, 15).millisecondsSinceEpoch);
      expect(w.endAt, DateTime(2026, 9, 7, 10, 55).millisecondsSinceEpoch);
      expect(w.leadMinutes, CourseCloudService.leadMinutes);
      expect(w.subtitle, '二教E101 · 10:15–10:55');
    });

    test('已经在上的课也收进来（切到流体云模式能立刻亮）', () {
      TimetableStore.instance.semesters = {'2026-3': semesterWithCourse()};
      final windows = CourseCloudService.planWindows(
          TimetableStore.instance, DateTime(2026, 9, 7, 10, 30), horizon: 1);
      expect(windows.single.endAt, DateTime(2026, 9, 7, 10, 55).millisecondsSinceEpoch);
    });

    test('改过上课时间就按新作息算（不再写死 10:10）', () {
      TimetableStore.slotStarts = List<String>.from(TimetableStore.slotStarts)..[2] = '10:20';
      TimetableStore.instance.semesters = {'2026-3': semesterWithCourse()};
      final windows = CourseCloudService.planWindows(
          TimetableStore.instance, DateTime(2026, 9, 7, 9, 0));
      expect(windows.single.startAt, DateTime(2026, 9, 7, 10, 20).millisecondsSinceEpoch);
    });

    test('下课之后再算就跳过这节（只排窗口期内还没结束的课）', () {
      TimetableStore.instance.semesters = {'2026-3': semesterWithCourse()};
      final windows = CourseCloudService.planWindows(
          TimetableStore.instance, DateTime(2026, 9, 7, 11, 30),
          horizon: 1);
      expect(windows, isEmpty);
    });
  });

  group('三选一', () {
    test('选完落盘：重启（重新 load）还是那个模式', () async {
      await CourseCloudService.I.setMode(CourseNotifyMode.cloud);
      expect(AppState.I.courseNotifyMode, CourseNotifyMode.cloud);

      await AppState.I.load();
      expect(AppState.I.courseNotifyMode, CourseNotifyMode.cloud, reason: '存在本机');

      await CourseCloudService.I.setMode(CourseNotifyMode.popup);
      expect(AppState.I.courseNotifyMode, CourseNotifyMode.popup);
    });

    test('流体云模式排窗口，其它模式清空', () async {
      TimetableStore.instance.semesters = {'2026-3': semesterWithCourse()};

      await CourseCloudService.I.setMode(CourseNotifyMode.cloud);
      expect(fake.scheduled, 1);
      expect(fake.windows, isNotEmpty, reason: '把未来 7 天的课程窗口交给原生闹钟');
      expect(fake.permissionAsked, isTrue, reason: '切过去时申请一次通知权限');

      await CourseCloudService.I.setMode(CourseNotifyMode.none);
      expect(fake.cleared, greaterThanOrEqualTo(1));
      expect(AppState.I.courseNotifyMode, CourseNotifyMode.none);
    });

    testWidgets('课程表设置里是三选一，点一下就切换并重排', (tester) async {
      TimetableStore.instance.semesters = {'2026-3': semesterWithCourse()};
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: TimetableSettingsPage(semesterKey: '2026-3')));
      await tester.pumpAndSettle();

      expect(find.text('课程通知方式'), findsOneWidget);
      expect(find.textContaining('弹窗通知'), findsOneWidget, reason: '默认弹窗');

      await tester.tap(find.text('课程通知方式'));
      await tester.pumpAndSettle();
      expect(find.text('不通知'), findsOneWidget);
      expect(find.text('流体云通知'), findsOneWidget);

      await tester.tap(find.text('流体云通知'));
      await tester.pumpAndSettle();
      expect(AppState.I.courseNotifyMode, CourseNotifyMode.cloud);
      expect(fake.windows, isNotEmpty);
      expect(find.textContaining('流体云通知'), findsWidgets, reason: '摘要跟着变');
    });

    testWidgets('小屏面板可滚动：最下面的预览按钮点得到', (tester) async {
      TimetableStore.instance.semesters = {'2026-3': semesterWithCourse()};
      await CourseCloudService.I.setMode(CourseNotifyMode.cloud);
      tester.view.physicalSize = const Size(720, 1280); // 360×640 逻辑像素
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          const MaterialApp(home: TimetableSettingsPage(semesterKey: '2026-3')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('课程通知方式'));
      await tester.pumpAndSettle();
      final button = find.text('预览流体云通知（1 分钟）');
      expect(button, findsOneWidget);

      // 内容比弹层高：往上滚，把最下面的按钮滚到屏幕内再点
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -420));
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(button).dy, lessThanOrEqualTo(640));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(fake.previews, 1);
    });
  });

  group('与上课提醒互斥', () {
    ClassReminder courseReminder() => ClassReminder(
          id: 1,
          at: DateTime(2026, 9, 7, 10),
          course: TtCourse(
            id: 'c1',
            name: '高等数学',
            day: 0,
            slotStart: 2,
            slotEnd: 2,
            weekType: 'all',
            weekStart: 1,
            weekEnd: 20,
          ),
        );
    ClassReminder eventReminder() => ClassReminder(
          id: 2,
          at: DateTime(2026, 9, 7, 11),
          event: TtEvent(
            id: 'e1',
            name: '班会',
            date: '2026-09-07',
            start: '11:00',
            end: '12:00',
          ),
        );

    test('只有弹窗模式排课程提醒；日程 / 考试提醒永远保留', () {
      final all = [courseReminder(), eventReminder()];

      expect(ClassReminderService.forMode(all, 'popup'), all);
      expect(ClassReminderService.forMode(all, 'none').single.event?.name, '班会');
      expect(ClassReminderService.forMode(all, 'cloud').single.event?.name, '班会');
    });
  });
}

/// 假的流体云能力：记录调用，不碰平台通道。
class _FakeCloud implements FluidCloudCapability {
  int scheduled = 0;
  int cleared = 0;
  int previews = 0;
  bool permissionAsked = false;
  List<FluidCloudWindow> windows = const [];

  @override
  Future<FluidCloudInfo> info() async => const FluidCloudInfo(
        vendor: 'coloros',
        label: 'ColorOS',
        apiLevel: 36,
        notificationsEnabled: true,
        exactAlarm: true,
        promotedSupported: true,
      );

  @override
  Future<void> show(FluidCloudWindow window) async {
    previews += 1;
  }

  @override
  Future<void> dismiss() async {}

  @override
  Future<int> schedule(List<FluidCloudWindow> list) async {
    scheduled += 1;
    windows = list;
    return list.length;
  }

  @override
  Future<void> clear() async {
    cleared += 1;
    windows = const [];
  }

  @override
  Future<bool> requestPermission() async {
    permissionAsked = true;
    return true;
  }
}
