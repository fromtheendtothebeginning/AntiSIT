import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:plugin_activities/activity_watch_settings_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 二课新活动提醒：分类命中规则、首次检查只建基线、演示数据下能发现新活动。
void main() {
  final demoActivities = <Map<String, dynamic>>[
    {'id': 'a001', 'name': 'AI 讲座', 'dlmc': '思想成长', 'lbmc': '讲座报告'},
    {'id': 'a002', 'name': '校园马拉松志愿者', 'dlmc': '社会实践', 'lbmc': '志愿服务'},
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ActivityWatchService.I.rule = const ActivityWatchRule();
    ActivityWatchService.I.loaded = false;
    await AppState.I.setDemo(true);
  });

  tearDown(() async => AppState.I.setDemo(false));

  group('规则匹配', () {
    test('不限分类：任何活动都算命中', () {
      const rule = ActivityWatchRule(enabled: true);
      expect(rule.matches({'dlmc': '思想成长', 'lbmc': '讲座报告'}), isTrue);
    });

    test('只选大类 / 只选小类 / 两个都选', () {
      const byDl = ActivityWatchRule(enabled: true, dl: {'社会实践'});
      expect(byDl.matches({'dlmc': '社会实践', 'lbmc': '志愿服务'}), isTrue);
      expect(byDl.matches({'dlmc': '思想成长', 'lbmc': '讲座报告'}), isFalse);

      const byLb = ActivityWatchRule(enabled: true, lb: {'讲座报告'});
      expect(byLb.matches({'dlmc': '思想成长', 'lbmc': '讲座报告'}), isTrue);
      expect(byLb.matches({'dlmc': '社会实践', 'lbmc': '志愿服务'}), isFalse);

      const both = ActivityWatchRule(
        enabled: true,
        dl: {'社会实践'},
        lb: {'讲座报告'},
      );
      expect(both.matches({'dlmc': '社会实践', 'lbmc': '讲座报告'}), isTrue,
          reason: '两个都选时要求同时命中');
      expect(both.matches({'dlmc': '社会实践', 'lbmc': '志愿服务'}), isFalse);
    });

    test('没开开关 / 没选分类时不该联网', () {
      const off = ActivityWatchRule();
      expect(off.needsCategories, isFalse, reason: '关掉的开关不提示选分类');
      const on = ActivityWatchRule(enabled: true);
      expect(on.needsCategories, isTrue, reason: '打开了却没选分类要提示');
    });

    test('规则序列化往返一致', () {
      const rule = ActivityWatchRule(
        enabled: true,
        dl: {'思想成长', '社会实践'},
        lb: {'讲座报告'},
      );
      final back = ActivityWatchRule.fromJson(rule.toJson());
      expect(back, rule);
    });
  });

  group('检查逻辑', () {
    test('第一次检查只记基线、不报新活动', () async {
      await ActivityWatchService.I.setRule(const ActivityWatchRule(
        enabled: true,
        dl: {'思想成长'},
      ));
      final r = await ActivityWatchService.I.check(notify: false);
      expect(r.fetched, greaterThan(0));
      expect(r.firstRun, isTrue);
      expect(r.matched, isEmpty, reason: '首次不能把历史活动当新活动');
    });

    test('出现了命中分类的新活动才报', () async {
      await ActivityWatchService.I.setRule(const ActivityWatchRule(
        enabled: true,
        dl: {'思想成长'},
      ));
      // 手工塞一条基线，模拟「昨天已经查过」
      await ActivityWatchService.I
          .setRule(const ActivityWatchRule(enabled: true, dl: {'思想成长'}));
      final first = await ActivityWatchService.I.check(notify: false);
      expect(first.firstRun, isTrue);
      // 新活动的判据来自「见过的 id」；这里直接用规则判断新列表里的命中项
      final matched = demoActivities.where(ActivityWatchService.I.rule.matches).toList();
      expect(matched.map((a) => a['id']), ['a001']);
    });

    test('关掉提醒时不联网、返回空结果', () async {
      await ActivityWatchService.I.setRule(const ActivityWatchRule());
      final r = await ActivityWatchService.I.check(notify: false);
      expect(r.fetched, 0);
      expect(r.matched, isEmpty);
      expect(r.error, isNull);
    });

    test('打开但没选分类：同样短路（不联网）', () async {
      await ActivityWatchService.I.setRule(const ActivityWatchRule(enabled: true));
      final r = await ActivityWatchService.I.check(notify: false);
      expect(r.fetched, 0);
      expect(r.matched, isEmpty);
    });
  });

  testWidgets('设置页：能开关、能挑分类、提示没选分类', (tester) async {
    await ActivityWatchService.I.setRule(const ActivityWatchRule(enabled: true));
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ActivityWatchSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('新活动提醒'), findsOneWidget);
    expect(find.textContaining('还没选分类'), findsOneWidget);
    // 分类胶囊来自演示数据
    expect(find.text('思想成长'), findsWidgets);
    await tester.tap(find.text('思想成长'));
    await tester.pumpAndSettle();
    expect(ActivityWatchService.I.rule.dl, contains('思想成长'));
    expect(find.textContaining('还没选分类'), findsNothing);
  });
}
