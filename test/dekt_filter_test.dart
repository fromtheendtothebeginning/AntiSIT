import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_activities/plugin_activities.dart';
import 'package:plugin_score/plugin_score.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 二课筛选的验收：加分明细 / 活动广场的类别 tag 筛选（一级 → 二级级联）
/// 与「拼音搜汉字」搜索（全拼 / 首字母都能命中）。
/// 页面用演示数据泵（demo_data 的活动 / 加分明细自带大类类别字段）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.I.demo = true;
  });
  tearDown(() => AppState.I.demo = false);

  group('拼音索引', () {
    test('全拼 / 首字母 / 原文任一命中即匹配', () {
      final s = PinyinSearchText('体育太极拳');
      expect(s.full, 'tiyutaijiquan');
      expect(s.matches('ty'), isTrue, reason: '首字母前缀');
      expect(s.matches('taiji'), isTrue, reason: '全拼片段');
      expect(s.matches('太极拳'), isTrue, reason: '汉字原文');
      expect(s.matches('tiyutaijiquan'), isTrue, reason: '全拼整串');
      expect(s.matches('xyz'), isFalse);
    });

    test('空查询恒匹配；大小写与空白不敏感；非汉字原样保留', () {
      expect(PinyinSearchText('AI 赋能讲座').matches(''), isTrue);
      expect(PinyinSearchText('AI 赋能讲座').matches('ai'), isTrue, reason: '原文小写匹配');
      expect(PinyinSearchText('2026 迎新').matches('2026'), isTrue);
      expect(PinyinSearchText('迎 新').matches('yx'), isTrue, reason: '空白不参与索引');
    });

    test('filterByPinyin：空查询原样返回，命中才保留', () {
      final items = ['程序设计基础', '太极拳体育', '马拉松'];
      expect(filterByPinyin(items, (x) => x, ''), items);
      expect(filterByPinyin(items, (x) => x, 'cx'), ['程序设计基础']);
      expect(filterByPinyin(items, (x) => x, 'taiji'), ['太极拳体育']);
    });
  });

  group('加分明细（第二课堂分）', () {
    Future<void> pumpScore(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ScorePage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('加分明细'));
      await tester.pumpAndSettle();
    }

    testWidgets('大类 tag 筛选 + 类别级联收窄', (tester) async {
      await pumpScore(tester);
      // 演示数据 3 条，两条劳育一条德育
      expect(find.text('3 条'), findsOneWidget);
      expect(find.text('AI 赋能学习效率提升讲座'), findsOneWidget);

      await tester.tap(find.text('劳育'));
      await tester.pumpAndSettle();

      expect(find.text('AI 赋能学习效率提升讲座'), findsNothing, reason: '德育那条被筛掉');
      expect(find.text('程序设计实践结项答辩'), findsOneWidget);
      expect(find.text('已筛出 2 / 3 条'), findsOneWidget);
      expect(find.text('讲座报告'), findsNothing, reason: '类别选项随大类级联收窄，德育下的「讲座报告」不再出现');
    });

    testWidgets('拼音搜索：首字母命中活动名，可再叠加类别筛选', (tester) async {
      await pumpScore(tester);

      await tester.enterText(find.byType(TextField), 'cx');
      await tester.pumpAndSettle();
      expect(find.text('程序设计实践结项答辩'), findsOneWidget, reason: '「程序」首字母 cx');
      expect(find.text('秋季校园马拉松志愿者'), findsNothing);
      expect(find.text('已筛出 1 / 3 条'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zy');
      await tester.pumpAndSettle();
      expect(find.text('秋季校园马拉松志愿者'), findsOneWidget, reason: '「志愿公益」类别首字母 zygy 命中 zy');
      expect(find.text('程序设计实践结项答辩'), findsNothing);
    });

    testWidgets('筛空时给「没有符合条件的记录」', (tester) async {
      await pumpScore(tester);
      await tester.enterText(find.byType(TextField), 'zzzzz');
      await tester.pumpAndSettle();
      expect(find.text('没有符合条件的记录'), findsOneWidget);
    });
  });

  group('活动广场（第二课堂活动）', () {
    Future<void> pumpActivities(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ActivitiesPage()));
      await tester.pumpAndSettle();
    }

    testWidgets('一级类别筛选 + 二级级联收窄', (tester) async {
      await pumpActivities(tester);
      // 演示数据 5 条：思想成长×2（讲座报告）、社会实践、创新创业、文体活动各 1
      expect(find.text('共 5 个活动'), findsOneWidget);

      await tester.tap(find.text('社会实践'));
      await tester.pumpAndSettle();
      expect(find.text('共 1 个活动'), findsOneWidget);
      expect(find.text('秋季校园马拉松志愿者'), findsOneWidget);
      expect(find.text('AI 赋能学习效率提升讲座'), findsNothing);

      // 二级类别选项只剩「志愿服务」（该大类下唯一），其他二级不再出现
      expect(find.text('文艺活动'), findsNothing);
    });

    testWidgets('拼音搜索：首字母命中活动名', (tester) async {
      await pumpActivities(tester);

      await tester.enterText(find.byType(TextField), 'mls');
      await tester.pumpAndSettle();
      expect(find.text('秋季校园马拉松志愿者'), findsOneWidget, reason: '「马拉松」首字母 mls');
      expect(find.text('共 1 个活动'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'geshou');
      await tester.pumpAndSettle();
      expect(find.text('校园十佳歌手大赛'), findsOneWidget, reason: '「歌手」全拼 geshou');
    });

    testWidgets('筛空时给「没有符合条件的活动」', (tester) async {
      await pumpActivities(tester);
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('没有符合条件的活动'), findsOneWidget);
      expect(find.text('共 0 个活动'), findsOneWidget);
    });
  });
}
