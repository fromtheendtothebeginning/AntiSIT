import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_grades/plugin_grades.dart';

/// 绩点计算器：批量选择（全选 / 除通识课全选 / 按类别 / 按学期）与加权绩点计算。
void main() {
  final grades = <Map<String, dynamic>>[
    {
      'kcmc': '高等数学',
      'cj': '92',
      'xf': '4.0',
      'jd': 4.2,
      'kclbmc': '学科专业基础课',
      'xnmmc': '2026-2027学年',
      'xqmmc': '第一学期',
    },
    {
      'kcmc': '大学英语',
      'cj': '88',
      'xf': '3.0',
      'jd': 3.8,
      'kclbmc': '通识课',
      'xnmmc': '2026-2027学年',
      'xqmmc': '第一学期',
    },
    {
      'kcmc': '程序设计基础',
      'cj': '95',
      'xf': '4.0',
      'jd': 4.5,
      'kclbmc': '学科专业基础课',
      'xnmmc': '2025-2026学年',
      'xqmmc': '第一学期',
    },
    {
      'kcmc': '军事理论',
      'cj': 'P',
      'xf': '1.0',
      'jd': null,
      'kclbmc': '通识课',
      'xnmmc': '2025-2026学年',
      'xqmmc': '第二学期',
    },
  ];

  group('纯逻辑', () {
    test('加权绩点 = Σ(绩点×学分)/Σ学分，缺绩点的课跳过并计数', () {
      final r = computeWeightedGpa(grades);
      expect(r.count, 3, reason: '「P」那门没有绩点，不参与');
      expect(r.skipped, 1);
      expect(r.credit, 11.0);
      // (4.2*4 + 3.8*3 + 4.5*4) / 11 = (16.8 + 11.4 + 18) / 11 = 46.2 / 11
      expect(r.gpa!.toStringAsFixed(4), (46.2 / 11).toStringAsFixed(4));
    });

    test('选空时不出现 NaN / 0 分这种假结果', () {
      final r = computeWeightedGpa(const []);
      expect(r.gpa, isNull);
      expect(r.credit, 0);
      expect(r.count, 0);
    });

    test('通识课判定：认「通识课」「通识教育」这类写法', () {
      expect(isGeneralCourse({'kclbmc': '通识课'}), isTrue);
      expect(isGeneralCourse({'kclbmc': '通识教育'}), isTrue);
      expect(isGeneralCourse({'kclbmc': '学科专业基础课'}), isFalse);
      expect(isGeneralCourse({'kclbmc': null}), isFalse);
    });

    test('课程键跨学期不串：同名课在不同学期是两条', () {
      final a = courseKeyOf({
        'kcmc': '高数',
        'xnmmc': '2025',
        'xqmmc': '第一学期',
        'xf': '4.0',
      });
      final b = courseKeyOf({
        'kcmc': '高数',
        'xnmmc': '2026',
        'xqmmc': '第一学期',
        'xf': '4.0',
      });
      expect(a, isNot(b));
    });

    test('类别 / 学期选项去重且保持出现顺序', () {
      expect(courseTagOptions(grades), ['学科专业基础课', '通识课']);
      expect(termOptions(grades), [
        '2026-2027学年 · 第一学期',
        '2025-2026学年 · 第一学期',
        '2025-2026学年 · 第二学期',
      ]);
    });
  });

  group('页面交互', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: GpaCalculatorPage(grades: grades)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('打开默认全选：加权绩点直接算出来', (tester) async {
      await open(tester);
      expect(find.text('绩点计算器'), findsOneWidget);
      expect(find.text('已选 3 门 · 11 学分'), findsOneWidget);
      expect(find.textContaining('1 门缺学分 / 绩点未参与计算'), findsOneWidget);
    });

    testWidgets('「除通识课全选」只留非通识课', (tester) async {
      await open(tester);
      await tester.tap(find.text('除通识课全选'));
      await tester.pumpAndSettle();
      // 只剩两门「学科专业基础课」：4 学分 + 4 学分，绩点 4.2 与 4.5
      expect(find.text('已选 2 门 · 8 学分'), findsOneWidget);
      expect(
        find.text('2 门缺学分 / 绩点未参与计算'),
        findsNothing,
        reason: '两门都有绩点，不该有跳过项',
      );
    });

    testWidgets('按类别胶囊批量加：通识课点一下就补回来', (tester) async {
      await open(tester);
      await tester.tap(find.text('除通识课全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('通识课').last);
      await tester.pumpAndSettle();
      // 补回两门通识课：3.0 学分有绩点、1.0 学分「P」没绩点
      expect(find.text('已选 3 门 · 11 学分'), findsOneWidget);
    });

    testWidgets('「清空」后不显示假绩点', (tester) async {
      await open(tester);
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 门 · 0 学分'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });
  });
}
