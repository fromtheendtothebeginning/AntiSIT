import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_activities/plugin_activities.dart';

/// 二课活动：名额满 / 条件不符时报名按钮直接显示对应状态；没标注的 tag 不画空胶囊。
void main() {
  group('学校失败文案 → 按钮状态', () {
    test('名额满', () {
      expect(signupBlockOfError('报名失败：名额已满'), SignupBlock.full);
      expect(signupBlockOfError('报名人数已满'), SignupBlock.full);
      expect(signupBlockOfError('该活动已满员'), SignupBlock.full);
    });

    test('条件不符', () {
      expect(signupBlockOfError('不符合报名条件'), SignupBlock.ineligible);
      expect(signupBlockOfError('资格不符'), SignupBlock.ineligible);
      expect(signupBlockOfError('不满足参与条件'), SignupBlock.ineligible);
    });

    test('识别不出的错误照常走弹窗', () {
      expect(signupBlockOfError('系统繁忙，请稍后重试'), isNull);
      expect(signupBlockOfError('已报名'), isNull);
    });
  });

  group('活动快照 / tag', () {
    test('报名人数达到名额 → isFullSignup；状态原文写着已满也算', () {
      expect(isFullSignup({'quota': '30 人', 'enrolled': 30}), isTrue);
      expect(isFullSignup({'quota': '30 人', 'enrolled': 29}), isFalse);
      expect(isFullSignup({'quota': '30 人', 'status_text': '名额已满'}), isTrue);
      expect(isFullSignup({'quota': '30 人', 'hdms': '报名人数已满，暂停报名'}), isTrue);
      expect(isFullSignup({'status_code': '4'}), isTrue, reason: '学校 hdbmzt=4 就是报名已满');
      expect(isFullSignup({'status_code': '6'}), isFalse, reason: 'hdbmzt=6 是无须报名');
      expect(isFullSignup({'quota': null, 'enrolled': 30}), isFalse, reason: '没名额信息无从判断');
    });

    test('条件不符只认学校明确状态，不从说明里猜', () {
      expect(isIneligibleSignup({'status_text': '条件不符'}), isTrue);
      expect(isIneligibleSignup({'status_text': '不符合报名条件'}), isTrue);
      expect(isIneligibleSignup({'hdms': '本活动仅限计算机学院学生'}), isFalse);
    });

    test('未标注的校区 / 空的大类小类不生成 tag', () {
      expect(campusTagOf({'campus': '未标注'}), '');
      expect(campusTagOf({'campus': ''}), '');
      expect(campusTagOf({'campus': null}), '');
      expect(campusTagOf({'campus': '奉贤'}), '奉贤');
      expect(categoryTextOf({'dlmc': '', 'lbmc': ''}), '');
      expect(categoryTextOf({'dlmc': '思想成长'}), '思想成长');
      expect(categoryTextOf({'dlmc': '思想成长', 'lbmc': '讲座报告'}), '思想成长 · 讲座报告');
    });

    test('快照透传报名人数与状态原文', () {
      final snap = activitySnapshot({
        'id': 'x',
        'hdmc': '满员讲座',
        'hdms': '名额：30 人',
        'bdrs': '30',
        'bmztmc': '名额已满',
      });
      expect(snap['enrolled'], 30);
      expect(snap['status_text'], '名额已满');
      expect(isFullSignup(snap), isTrue);
    });
  });

  group('活动广场状态胶囊', () {
    String dt(DateTime t) =>
        t.toIso8601String().replaceFirst('T', ' ').substring(0, 19);

    Map<String, dynamic> act({required bool full, bool ended = false}) {
      final now = DateTime.now();
      return {
        'bm_start': dt(now.subtract(const Duration(days: 2))),
        'bm_end': dt(ended ? now.subtract(const Duration(days: 1)) : now.add(const Duration(days: 1))),
        'quota': '30 人',
        if (full) 'enrolled': 30,
      };
    }

    test('报名中且满员 → 直接显示「已人满」', () {
      expect(marketStateText(act(full: true)), '已人满');
    });

    test('报名中未满 → 仍显示「报名中」', () {
      expect(marketStateText(act(full: false)), '报名中');
    });

    test('已结束不显示满员标记', () {
      expect(marketStateText(act(full: true, ended: true)), '报名已结束');
    });
  });

  testWidgets('详情页：报名人数满了 → 按钮显示「人满，不可报名」且禁用', (tester) async {
    AppState.I.demo = true;
    addTearDown(() => AppState.I.demo = false);

    await tester.pumpWidget(const MaterialApp(
      home: ActivityDetailPage(id: 'a001', activity: {
        'id': 'a001',
        'name': 'AI 赋能学习效率提升讲座',
        'bm_start': '2020-01-01 00:00:00',
        'bm_end': '2099-12-31 23:59:00',
        'start': '2099-11-01 14:00:00',
        'end': '2099-11-01 16:00:00',
        'quota': '200 人',
        // 演示详情不会回报名人数，这个值会保留下来
        'enrolled': 200,
      }),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('人满，不可报名'), matching: find.bySubtype<FilledButton>()));
    expect(button.onPressed, isNull, reason: '满员后不能再报名');
    expect(find.text('在线报名'), findsNothing);
  });

  testWidgets('详情页：学校状态写着条件不符 → 按钮显示「条件不符」且禁用', (tester) async {
    AppState.I.demo = true;
    addTearDown(() => AppState.I.demo = false);

    await tester.pumpWidget(const MaterialApp(
      home: ActivityDetailPage(id: 'a001', activity: {
        'id': 'a001',
        'name': 'AI 赋能学习效率提升讲座',
        'bm_start': '2020-01-01 00:00:00',
        'bm_end': '2099-12-31 23:59:00',
        'start': '2099-11-01 14:00:00',
        'end': '2099-11-01 16:00:00',
        'status_text': '条件不符',
      }),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('条件不符'), matching: find.bySubtype<FilledButton>()));
    expect(button.onPressed, isNull);
  });
}
