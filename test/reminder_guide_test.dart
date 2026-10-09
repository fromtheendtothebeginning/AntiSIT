import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_reminder/plugin_reminder.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 上课提醒的引导分两层：
/// * 设置列表里开关下面只留**一行摘要**（状态 + 待处理项数），不占地方；
/// * 状态详情、一件件的「去系统设置」以及「为什么提醒不来」的说明，
///   都在二级页 [ReminderGuidePage]。
///
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

void main() {
  const systemChannel = MethodChannel('antisit/system');
  final systemCalls = <String>[];

  /// 自检是异步探测（平台通道 + 插件查询），多 pump 几帧让 Future 链跑完；
  /// 页面上的「自检中…」不是动画，pumpAndSettle 等不到它。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  setUp(() async {
    systemCalls.clear();
    FlutterLocalNotificationsPlatform.instance = _FakeAndroidNotifications();
    SharedPreferences.setMockInitialValues({'flutter.class_reminder_on': true});
    await ClassReminderService.I.loadEnabled();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(systemChannel, (MethodCall call) async {
      systemCalls.add(call.method);
      return switch (call.method) {
        'isIgnoringBatteryOptimizations' => true, // 默认：后台没被限制，各用例按需改
        _ => true,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(systemChannel, null);
  });

  /// 只灌设置列表里插件贡献的那几个条目。
  Future<void> pumpTiles(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return Column(
              children: const ReminderPlugin().settingsTiles(context, PluginRegistry()));
        }),
      ),
    ));
    await settle(tester);
  }

  Future<void> pumpGuidePage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReminderGuidePage()));
    await settle(tester);
  }

  group('设置列表里的一行摘要', () {
    testWidgets('正常时一句话带过，详情不在列表里', (tester) async {
      await pumpTiles(tester);
      expect(find.text('提醒自检与引导'), findsOneWidget);
      expect(find.textContaining('状态正常'), findsOneWidget);
      expect(find.text('通知权限'), findsNothing, reason: '详情应该收进二级页，不占设置列表');
      expect(find.text('去设置'), findsNothing);
    });

    testWidgets('有问题时摘要直接点出来（红色 + 待处理项数）', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(systemChannel, (MethodCall call) async {
        systemCalls.add(call.method);
        return switch (call.method) {
          'isIgnoringBatteryOptimizations' => false,
          _ => true,
        };
      });
      await pumpTiles(tester);
      expect(find.textContaining('后台运行受限制（1 项待处理）'), findsOneWidget);
    });

    testWidgets('提醒关着时连摘要都不显示', (tester) async {
      SharedPreferences.setMockInitialValues({'flutter.class_reminder_on': false});
      await ClassReminderService.I.loadEnabled();
      await pumpTiles(tester);
      expect(find.text('提醒自检与引导'), findsNothing);
    });

    testWidgets('点摘要能进二级页', (tester) async {
      await pumpTiles(tester);
      await tester.tap(find.text('提醒自检与引导'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.text('提醒状态正常'), findsOneWidget);
      expect(find.text('通知权限'), findsOneWidget);
    });
  });

  group('二级页：状态与引导', () {
    testWidgets('三项正常：给结论 + 排期条数 + 说明为什么还要看系统', (tester) async {
      await pumpGuidePage(tester);
      expect(find.text('提醒状态正常'), findsOneWidget);
      expect(find.text('通知权限'), findsOneWidget);
      expect(find.text('精确闹钟'), findsOneWidget);
      expect(find.text('后台运行'), findsOneWidget);
      expect(find.text('已排除电池优化'), findsOneWidget);
      expect(find.textContaining('未来 30 天'), findsOneWidget);
      expect(find.text('提醒不来的常见原因'), findsOneWidget);
      expect(find.textContaining('省电策略'), findsWidgets);
      expect(find.text('去设置'), findsNothing, reason: '都正常就没有要动的地方');
    });

    testWidgets('后台受限：结论是「还有 1 项需要处理」，并能一键去设置', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(systemChannel, (MethodCall call) async {
        systemCalls.add(call.method);
        return switch (call.method) {
          'isIgnoringBatteryOptimizations' => false,
          _ => true,
        };
      });
      await pumpGuidePage(tester);
      expect(find.text('还有 1 项需要处理'), findsOneWidget);
      expect(find.textContaining('受省电策略限制'), findsOneWidget);

      await tester.tap(find.text('去设置'));
      await tester.pumpAndSettle();
      expect(systemCalls, contains('openBatteryOptimizationSettings'));
    });

    testWidgets('通知权限没给：指出「通知根本不会出现」并能去开', (tester) async {
      FlutterLocalNotificationsPlatform.instance =
          _FakeAndroidNotifications(notifications: false);
      await pumpGuidePage(tester);
      expect(find.textContaining('通知根本不会出现'), findsOneWidget);
      await tester.tap(find.text('去开启'));
      await tester.pumpAndSettle();
      expect(systemCalls, contains('openNotificationSettings'));
    });

    testWidgets('精确闹钟没允许：说明只会不精确触发', (tester) async {
      FlutterLocalNotificationsPlatform.instance = _FakeAndroidNotifications(exact: false);
      await pumpGuidePage(tester);
      expect(find.textContaining('未允许：只能不精确触发'), findsOneWidget);
      expect(find.text('去允许'), findsOneWidget);
    });

    testWidgets('课表里没有课时排期行给出「没有要提醒的课」', (tester) async {
      await pumpGuidePage(tester);
      expect(find.text('没有要提醒的课'), findsOneWidget);
    });
  });
}
