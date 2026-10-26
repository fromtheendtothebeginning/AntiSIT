import 'dart:convert';

import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_score/plugin_score.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 三级页面：按年级调整本机达标线，保存/恢复默认。
void main() {
  setUp(() {
    AppState.I.creds.grade = '2027';
    SharedPreferences.setMockInitialValues({
      // 预置一份新鲜缓存，避免测试里真的去拉远端。
      'score_targets_v1': jsonEncode({
        'default': {
          'total': 8,
          'groups': [
            {'keywords': ['德育'], 'target': 3},
            {'keywords': ['美育'], 'target': 1, 'noExpand': true},
          ],
          'subs': [
            {'keywords': ['讲座', '报告'], 'target': 1.8},
          ],
        },
      }),
      'score_targets_v1_at': DateTime.now().millisecondsSinceEpoch,
    });
  });

  testWidgets('保存本机达标线并可恢复默认', (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: ScoreTargetSettingsPage(cohort: '2027')));
    await tester.pumpAndSettle();

    expect(find.text('当前年级 2027'), findsOneWidget);
    expect(find.text('实践学分总目标'), findsOneWidget);
    expect(find.text('美育'), findsOneWidget);

    // 第一个输入框是实践学分总目标
    await tester.enterText(find.byType(TextField).first, '9');
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.byType(FilledButton), 300, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('score_targets_local_v1'), contains('"total":9'));
    expect(find.text('已保存本机达标线'), findsOneWidget);

    await tester.scrollUntilVisible(find.byType(OutlinedButton), 300, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(sp.getString('score_targets_local_v1'), isNull);
  });

  testWidgets('未填年级时提示去直连设置', (tester) async {
    AppState.I.creds.grade = '';
    await tester.pumpWidget(
        const MaterialApp(home: ScoreTargetSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('未填写年级'), findsOneWidget);
    expect(find.text('去直连设置填写年级'), findsOneWidget);
  });
}
