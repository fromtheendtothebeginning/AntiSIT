import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_reminder/plugin_reminder.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假的 Android 通知平台实现：测试进程里没有真的平台通道，
/// 用官方那套 `FlutterLocalNotificationsPlatform.instance` 注入点伪造两项权限状态。
class _FakeAndroidNotifications extends AndroidFlutterLocalNotificationsPlugin {
  _FakeAndroidNotifications({this.notifications = true, this.exact = true});

  final bool notifications;
  final bool exact;

  @override
  Future<bool?> areNotificationsEnabled() async => notifications;

  @override
  Future<bool?> canScheduleExactNotifications() async => exact;
}

/// 上课提醒的引导：排期成功 ≠ 能弹出来。通知权限 / 精确闹钟 / 后台省电策略
/// 任意一项不对，用户那边都是「提醒不来」，而这三项只有系统设置页能改——
/// 所以开关下面要能看见状态、并一键跳过去。
void main() {
  const systemChannel = MethodChannel('antisit/system');
  final systemCalls = <String>[];

  setUp(() async {
    systemCalls.clear();
    FlutterLocalNotificationsPlatform.instance = _FakeAndroidNotifications();
    // 提醒开着，才需要自检
    SharedPreferences.setMockInitialValues({'flutter.class_reminder_on': true});
    await ClassReminderService.I.loadEnabled();

    tester0(MethodCall call) {
      systemCalls.add(call.method);
      return switch (call.method) {
        'isIgnoringBatteryOptimizations' => true, // 默认：后台没被限制，逐条改
        'openBatteryOptimizationSettings' => true,
        'openAppInfoSettings' => true,
        'openNotificationSettings' => true,
        _ => null,
      };
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(systemChannel, (call) async => tester0(call));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(systemChannel, null);
  });

  Future<void> pumpTile(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          final tiles = const ReminderPlugin().settingsTiles(context, PluginRegistry());
          return Column(children: tiles);
        }),
      ),
    ));
    // 自检是异步探测（平台通道 + 插件查询），多 pump 几帧让 Future 链跑完，
    // 别用 pumpAndSettle——它只等动画，不等这些 Future
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('三项正常时给出「都正常」的结论，没有要去开的动作', (tester) async {
    await pumpTile(tester);
    expect(find.text('通知权限'), findsOneWidget);
    expect(find.text('精确闹钟'), findsOneWidget);
    expect(find.text('后台运行'), findsOneWidget);
    expect(find.text('已排除电池优化'), findsOneWidget);
    expect(find.textContaining('三项都正常'), findsOneWidget);
    expect(find.text('去设置'), findsNothing);
  });

  testWidgets('后台被省电策略限制：明确告知 + 一键去设置', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(systemChannel, (MethodCall call) async {
      systemCalls.add(call.method);
      return switch (call.method) {
        'isIgnoringBatteryOptimizations' => false, // 受限制
        _ => true,
      };
    });
    await pumpTile(tester);

    expect(find.textContaining('受省电策略限制'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
    expect(find.textContaining('省电策略 / 自启动'), findsOneWidget); // 厂商机型提示

    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();
    expect(systemCalls, contains('openBatteryOptimizationSettings'));
  });

  testWidgets('通知权限没给：指出「根本弹不出来」并能去开', (tester) async {
    FlutterLocalNotificationsPlatform.instance =
        _FakeAndroidNotifications(notifications: false);
    await pumpTile(tester);

    expect(find.textContaining('提醒根本弹不出来'), findsOneWidget);
    await tester.tap(find.text('去开启'));
    await tester.pumpAndSettle();
    expect(systemCalls, contains('openNotificationSettings'));
  });

  testWidgets('精确闹钟没允许：说明只会不精确触发，并能去允许', (tester) async {
    FlutterLocalNotificationsPlatform.instance =
        _FakeAndroidNotifications(exact: false);
    await pumpTile(tester);

    expect(find.textContaining('只能不精确触发'), findsOneWidget);
    expect(find.text('去允许'), findsOneWidget);
  });

  testWidgets('提醒关着时不显示自检（不占地方）', (tester) async {
    SharedPreferences.setMockInitialValues({'flutter.class_reminder_on': false});
    await ClassReminderService.I.loadEnabled();
    await pumpTile(tester);
    expect(find.text('通知权限'), findsNothing);
    expect(find.textContaining('三项都正常'), findsNothing);
  });
}
