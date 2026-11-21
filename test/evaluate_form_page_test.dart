import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_evaluate/plugin_evaluate.dart';

/// 评分页的界面要素与批量打分的口径。
/// 网络层被替身挡住（页面在 initState 里就要取表单），这里只看「界面该有的东西在不在」。
void main() {
  test('批量打分遇到已提交的条目会跳过（不覆盖已提交评教）', () async {
    final result = await fillAllTargets(
      api: EvaluateApi(session: EvaluateSession(fallbackBase: 'https://jwxt.invalid')),
      targets: const [
        EvalTarget(
          jxbId: 'J',
          kchId: 'K',
          jghId: 'G',
          sfcjlrjs: '1',
          tjzt: '1',
          course: '课',
          teacher: '师',
          className: '',
        ),
      ],
      score: 95,
    );
    expect(result.done, 0);
    expect(result.skipped, 1);
    expect(result.failures, isEmpty);
    expect(result.ok, isTrue);
  });

  test('批量提交同样跳过已提交的条目', () async {
    final result = await submitAllTargets(
      api: EvaluateApi(session: EvaluateSession(fallbackBase: 'https://jwxt.invalid')),
      targets: const [
        EvalTarget(
          jxbId: 'J',
          kchId: 'K',
          jghId: 'G',
          sfcjlrjs: '1',
          tjzt: '1',
          course: '课',
          teacher: '师',
          className: '',
        ),
      ],
      score: 95,
    );
    expect(result.done, 0);
    expect(result.skipped, 1);
    expect(result.ok, isTrue);
  });

  test('一键打分把统一分数摊到全部指标（按各自范围吸附）', () {
    const form = EvalForm(
      jxbId: 'J',
      kchId: 'K',
      jghId: 'G',
      xsdm: '01',
      ztpjbl: '100',
      jszdpjbl: '0',
      xykzpjbl: '0',
      models: [
        EvalModel(
          id: 'M',
          name: '模板',
          pjdxdm: '01',
          fxzgf: '',
          savedId: '',
          groups: [
            EvalGroup(
              id: 'GA',
              title: '一、目标明确度',
              weight: 1,
              items: [
                EvalItem(
                  id: 'A',
                  text: '题一',
                  required: true,
                  min: 0,
                  max: 100,
                  gradeCodeId: 'GC',
                  templateCodeId: 'TC',
                ),
                EvalItem(
                  id: 'B',
                  text: '题二',
                  required: true,
                  min: 0,
                  max: 20,
                  gradeCodeId: 'GC',
                  templateCodeId: 'TC',
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final scores = presetScores(form, 95);
    expect(scores['A'], 95);
    expect(scores['B'], 20, reason: '超出该指标上限时夹到 20');
    expect(form.total(scores), closeTo(1 * 1 * 95 + 1 * 1 * 20, 1e-6));
  });

  testWidgets('列表页两个批量按钮用同一种按钮形式', (tester) async {
    var filled = 0;
    var submitted = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EvaluateListView(
          summary: const EvalSummary(pending: 1, saved: 0, submitted: 0),
          targets: const [
            EvalTarget(
              jxbId: 'J',
              kchId: 'K',
              jghId: 'G',
              sfcjlrjs: '1',
              tjzt: '-1',
              course: '离散数学',
              teacher: '马秀莹',
              className: '2602121',
            ),
          ],
          onFillAll: () async {
            filled++;
          },
          onSubmitAll: () async {
            submitted++;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('全部打分'), findsOneWidget);
    expect(find.text('全部提交'), findsOneWidget);

    // 两个按钮必须是同一种组件（用户要求：统一按钮形式，不突出其中一个）
    final buttons = tester
        .widgetList<Widget>(find.byWidgetPredicate((w) => w is FilledButton))
        .toList();
    expect(buttons, hasLength(2));
    expect(buttons[0].runtimeType, buttons[1].runtimeType);
    for (final b in buttons) {
      expect((b as FilledButton).onPressed, isNotNull);
    }

    await tester.tap(find.text('全部打分'));
    await tester.pumpAndSettle();
    expect(filled, 1);

    await tester.tap(find.text('全部提交'));
    await tester.pumpAndSettle();
    expect(submitted, 1);
  });
}