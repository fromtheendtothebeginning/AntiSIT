import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_core/campus_core.dart';
import 'package:plugin_evaluate/evaluate_batch.dart';
import 'package:plugin_evaluate/plugin_evaluate.dart';

/// 评分页的界面要素：统一分数滑条 / 预设档位 / 一键给全部老师打分 / 提交前二次确认。
/// 网络层被替身挡住（页面在 initState 里就要取表单），这里只看「界面该有的东西在不在」。
void main() {
  testWidgets('设置页可以填代理地址与端口，并且说明凭据只存本机', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EvaluateSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('校园代理（SOCKS5）'), findsOneWidget);
    expect(find.text('地址'), findsOneWidget);
    expect(find.text('端口'), findsOneWidget);
    expect(find.textContaining('不会写进仓库'), findsOneWidget);
    expect(find.text('保存设置'), findsOneWidget);
  });

  test('批量打分遇到已提交的条目会跳过（不覆盖已提交评教）', () async {
    final result = await fillAllTargets(
      api: EvaluateApi(
        base: 'https://jwxt.invalid',
        session: EvaluateSession(persistKey: 'batch_test'),
        proxy: SocksProxy.none,
      ),
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
      api: EvaluateApi(
        base: 'https://jwxt.invalid',
        session: EvaluateSession(persistKey: 'batch_submit_test'),
        proxy: SocksProxy.none,
      ),
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
    final form = EvalForm(
      jxbId: 'J',
      kchId: 'K',
      jghId: 'G',
      xsdm: '01',
      ztpjbl: '100',
      jszdpjbl: '0',
      xykzpjbl: '0',
      models: const [
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
}