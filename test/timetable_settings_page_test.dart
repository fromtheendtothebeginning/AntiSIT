import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_reminder/plugin_reminder.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 需求：上课提醒、上完的课淡化显示收进「课程表设置」二级页，
/// 课表页的「学期设置」「调休设置」也一并收进去；入口两处
/// （课表页右上角菜单 /「我的 → 设置」），进的是同一页。
void main() {
  /// 带提醒插件的注册表：验证两页各自的条目。
  PluginRegistry registry() => PluginRegistry(
        features: const [TimetablePlugin(), ReminderPlugin()],
        capabilities: const {PluginIds.reminder: ReminderCapabilityImpl()},
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    await ClassReminderService.I.loadEnabled();
    AppState.I.dimCompleted = true;
    TimetableStore.instance.semesters = {};
    TimetableStore.instance.active = '';
    PluginRegistry.I = registry();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  /// 某一行开关的当前值。
  bool? switchValue(WidgetTester tester, String title) => tester
      .widget<SwitchListTile>(find.ancestor(
          of: find.text(title), matching: find.byType(SwitchListTile)))
      .value;

  /// 只灌某一批设置条目（「我的 → 设置」那批 / 课表设置页那批）。
  Future<void> pumpTiles(WidgetTester tester, List<Widget> Function(BuildContext) tiles) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) => Column(children: tiles(c)))),
    ));
    await tester.pumpAndSettle();
  }

  group('「课程表设置」二级页', () {
    testWidgets('四行都在：学期 / 调休 / 上课提醒 / 上完的课淡化显示', (tester) async {
      await pump(tester, const TimetableSettingsPage(semesterKey: '2026-3'));
      expect(find.text('课程表设置'), findsOneWidget, reason: '页面标题');
      expect(find.text('学期设置'), findsOneWidget);
      expect(find.text('调休设置'), findsOneWidget);
      expect(find.text('上课提醒'), findsOneWidget, reason: '提醒插件的条目投在这一页');
      expect(find.text('上完的课淡化显示'), findsOneWidget);
    });

    testWidgets('从「我的」进来（不带学期）：改的是课表最近显示过的那个学期', (tester) async {
      TimetableStore.instance.active = '2026-3';
      final tt = TimetableStore.instance.semester('2026', '3');
      tt.startDate = '2025-09-01';
      tt.weekCount = 18;

      await pump(tester, const TimetableSettingsPage());
      expect(find.textContaining('起点 2025-09-01 · 共 18 周'), findsOneWidget);
    });

    testWidgets('学期设置 / 调休设置点开还是那两个弹窗（没被搬走，只是收进来了）', (tester) async {
      await pump(tester, const TimetableSettingsPage(semesterKey: '2026-3'));

      await tester.tap(find.text('学期设置'));
      await tester.pumpAndSettle();
      expect(find.text('学期起点（第 1 周周一）'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20)); // 点空白处关掉弹窗
      await tester.pumpAndSettle();

      await tester.tap(find.text('调休设置'));
      await tester.pumpAndSettle();
      expect(find.text('暂无调休规则'), findsOneWidget);
    });

    testWidgets('提醒插件停用后，这一页里就没有上课提醒', (tester) async {
      PluginRegistry.I = PluginRegistry(features: const [TimetablePlugin()]);
      await pump(tester, const TimetableSettingsPage(semesterKey: '2026-3'));
      expect(find.text('上课提醒'), findsNothing);
      expect(find.text('上完的课淡化显示'), findsOneWidget, reason: '课表自己的条目照旧');
    });

    testWidgets('淡化显示的开关点得动，界面跟着重绘', (tester) async {
      AppState.I.setDimCompleted(true);
      await pump(tester, const TimetableSettingsPage(semesterKey: '2026-3'));
      expect(switchValue(tester, '上完的课淡化显示'), isTrue);

      await tester.tap(find.text('上完的课淡化显示'));
      await tester.pumpAndSettle();
      expect(AppState.I.dimCompleted, isFalse);
      expect(switchValue(tester, '上完的课淡化显示'), isFalse, reason: '得跟着重绘，不能看着像卡住');
    });
  });

  group('入口', () {
    testWidgets('课表页菜单：学期 / 调休 收进「课程表设置」，点进去就是那一页', (tester) async {
      PluginRegistry.I = PluginRegistry(features: const [TimetablePlugin()]);
      await pump(tester, const TimetablePage());

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('课程表设置'), findsOneWidget);
      expect(find.text('学期设置'), findsNothing, reason: '不再直接挂在菜单上');
      expect(find.text('调休设置'), findsNothing);

      await tester.tap(find.text('课程表设置'));
      await tester.pumpAndSettle();
      expect(find.text('学期设置'), findsOneWidget);
      expect(find.text('调休设置'), findsOneWidget);
    });

    testWidgets('「我的 → 设置」里只剩一行入口：两个开关都搬走了', (tester) async {
      await pumpTiles(tester, (c) => PluginRegistry.I.settingsTiles(c));
      expect(find.text('课程表设置'), findsOneWidget);
      expect(find.text('上课提醒'), findsNothing);
      expect(find.text('上完的课淡化显示'), findsNothing);
    });

    testWidgets('「课程表设置」那批条目：只有两个开关，没有入口行', (tester) async {
      await pumpTiles(tester, (c) => PluginRegistry.I.timetableSettingsTiles(c));
      expect(find.text('上课提醒'), findsOneWidget);
      expect(find.text('上完的课淡化显示'), findsOneWidget);
      expect(find.text('课程表设置'), findsNothing, reason: '入口只在「我的」那边');
    });
  });
}
