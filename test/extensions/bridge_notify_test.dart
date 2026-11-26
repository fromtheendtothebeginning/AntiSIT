import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpExtensionEnv();

  group('接口：页面栈返回 + 通知', () {
    late ExtNotificationService original;
    late FakeNotifier notifier;

    setUp(() {
      original = ExtNotificationService.instance;
      notifier = FakeNotifier();
      ExtNotificationService.instance = notifier;
    });

    tearDown(() => ExtNotificationService.instance = original);

    Future<ExtBridge> bridge(WidgetTester tester, {ExtensionItem? item}) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      return ExtBridge(
        extId: 'e1',
        context: tester.element(find.byType(SizedBox)),
        item: item,
      );
    }

    testWidgets('ui.backDepth 把页面栈深度告诉内核（系统返回先回退栈内页面）', (tester) async {
      final b = await bridge(tester);
      bool? canGoBack;
      b.attachBackGuard((value) => canGoBack = value);

      expect(await b.call('ui.backDepth', {'depth': 2}), isTrue);
      expect(canGoBack, isTrue, reason: '栈里还有页面 → 返回键先交给网页');
      await b.call('ui.backDepth', {'depth': 0});
      expect(canGoBack, isFalse, reason: '栈空了 → 返回键关整页');
    });

    testWidgets('notify.show / schedule / cancel / cancelAll：参数原样交出去', (
      tester,
    ) async {
      final b = await bridge(tester);

      expect(
        await b.call('notify.show', {
          'title': ' 提醒 ',
          'body': ' 正文 ',
          'key': 'k1',
        }),
        isTrue,
      );
      expect(notifier.calls.last, 'show');
      expect(notifier.extId, 'e1');
      expect(notifier.key, 'k1');
      expect(notifier.title, '提醒', reason: '两端空白去掉');
      expect(notifier.body, '正文');

      final at = DateTime.now().add(const Duration(hours: 1));
      expect(
        await b.call('notify.schedule', {
          'key': 'k2',
          'title': '到点了',
          'at': at.toIso8601String(),
        }),
        isTrue,
      );
      expect(notifier.calls.last, 'schedule');
      expect(notifier.at!.difference(at).inSeconds.abs(), lessThan(1));

      expect(
        await b.call('notify.schedule', {
          'key': 'k3',
          'title': '时间戳',
          'at': at.millisecondsSinceEpoch,
        }),
        isTrue,
      );
      expect(notifier.at!.difference(at).inSeconds.abs(), lessThan(1));

      expect(await b.call('notify.cancel', {'key': 'k1'}), isTrue);
      expect(notifier.calls.last, 'cancel');
      expect(await b.call('notify.cancelAll', null), isTrue);
      expect(notifier.calls.last, 'cancelAll');
    });

    testWidgets('通知参数不对直接报错，不静默失败', (tester) async {
      final b = await bridge(tester);
      await expectLater(b.call('notify.show', null), throwsArgumentError);
      await expectLater(
        b.call('notify.show', {'title': '   '}),
        throwsArgumentError,
      );
      await expectLater(
        b.call('notify.show', {'title': 'x' * 201}),
        throwsArgumentError,
        reason: '标题过长',
      );
      await expectLater(
        b.call('notify.schedule', {
          'title': 'x',
          'at': DateTime.now().toIso8601String(),
        }),
        throwsArgumentError,
        reason: 'schedule 必须带 key（取消靠它）',
      );
      await expectLater(
        b.call('notify.schedule', {'key': 'k', 'title': 'x'}),
        throwsArgumentError,
        reason: 'schedule 必须带 at',
      );
      await expectLater(
        b.call('notify.schedule', {
          'key': 'k',
          'title': 'x',
          'at': DateTime.now()
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
        }),
        throwsArgumentError,
        reason: '过去的时间排了也不会响',
      );
      expect(notifier.calls, isEmpty, reason: '参数校验就该拦下');
    });

    testWidgets('市场装的拓展必须声明 notification 权限', (tester) async {
      final denied = await bridge(
        tester,
        item: marketExtItem(permissions: const ['storage']),
      );
      await expectLater(
        denied.call('notify.show', {'title': 'x'}),
        throwsArgumentError,
      );
      expect(notifier.calls, isEmpty);

      final allowed = await bridge(
        tester,
        item: marketExtItem(permissions: const ['notification']),
      );
      expect(await allowed.call('notify.show', {'title': 'x'}), isTrue);
      expect(notifier.calls, ['show']);
    });
  });
}

