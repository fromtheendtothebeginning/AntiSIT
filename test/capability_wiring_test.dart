import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_reminder/plugin_reminder.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 能力注册表在 UI 上的效果：课表页那颗「上课提醒」铃铛挂在**提醒能力**上——
/// 提供方（plugin_reminder）在不在，决定铃铛在不在。课表不 import 那个包。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    final monday = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
    final (xnm, xqm) = AppState.inferSemester(DateTime.now());
    TimetableStore.instance.semesters = {
      '$xnm-$xqm': SemesterTt(startDate: TimetableStore.iso(monday), weekCount: 20),
    };
    TimetableStore.instance.active = '$xnm-$xqm';
  });

  PluginRegistry registry() => PluginRegistry(
        features: const [TimetablePlugin(), ReminderPlugin()],
        themes: const [GlassTheme()],
        // 提供方声明自己提供的能力（真实实现，落在 plugin_reminder 包里）
        capabilities: const {PluginIds.reminder: ReminderCapabilityImpl()},
      );

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: TimetablePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Finder bell() => find.byWidgetPredicate((w) =>
      w is Icon &&
      (w.icon == Icons.notifications_active || w.icon == Icons.notifications_off_outlined));

  testWidgets('提醒插件在 → 铃铛在；把它停用 → 铃铛消失（能力查不到）', (tester) async {
    PluginRegistry.I = registry();
    expect(PluginRegistry.I.capability<ReminderCapability>(PluginIds.reminder), isNotNull);
    await pumpPage(tester);
    expect(bell(), findsOneWidget, reason: '能力在，铃铛就该在');

    await PluginRegistry.I.disable('reminder');
    await tester.pump();
    expect(PluginRegistry.I.capability<ReminderCapability>(PluginIds.reminder), isNull);
    expect(bell(), findsNothing, reason: '停用后取不到能力，铃铛整颗不出现');

    await PluginRegistry.I.enable('reminder');
    await tester.pump();
    expect(bell(), findsOneWidget, reason: '开回来铃铛也回来');
  });
}
