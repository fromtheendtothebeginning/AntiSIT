import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_evaluate/plugin_evaluate.dart';

/// 评分助手面板：统一分数一条滑块（拖着就打到全部）+ 逐项一条滑块（一拖就改这一项）。
/// 面板不碰 WebView，所有改分都走回调，所以这里能直接把交互钉住。
const _items = [
  EvalItem(
    index: 0,
    label: '教学态度认真',
    kind: 'text',
    value: 0,
    min: 0,
    max: 100,
    values: [],
  ),
  EvalItem(
    index: 1,
    label: '内容充实',
    kind: 'text',
    value: 0,
    min: 0,
    max: 100,
    values: [],
  ),
  EvalItem(
    index: 2,
    label: '作业适量',
    kind: 'text',
    value: 0,
    min: 0,
    max: 100,
    values: [],
  ),
];

Widget _wrap({
  EvaluatePanelState state = const EvaluatePanelState(items: _items),
  ValueChanged<double>? onApplyAll,
  void Function(EvalItem, double)? onApplyOne,
  VoidCallback? onRescan,
  VoidCallback? onLogin,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 520,
          child: EvaluatePanel(
            state: state,
            onApplyAll: onApplyAll ?? (_) {},
            onApplyOne: onApplyOne ?? (_, __) {},
            onRescan: onRescan ?? () {},
            onLogin: onLogin ?? () {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('统一分数默认取最高分；拖动过程中就把分数打到全部项', (tester) async {
    final applied = <double>[];
    await tester.pumpWidget(_wrap(onApplyAll: applied.add));

    expect(find.text('拖到哪就打到哪：当前 100 分 → 这一页全部 3 项'), findsOneWidget);
    expect(find.text('一键同分'), findsNothing, reason: '按钮已去掉：拖动即同分');

    await tester.drag(find.byType(Slider).first, const Offset(-220, 0));
    await tester.pumpAndSettle();

    expect(applied, isNotEmpty, reason: '拖动过程中就要下发，不用等松手');
    expect(applied.every((v) => v == v.roundToDouble()), isTrue,
        reason: '百分制分值必须是整数，不能出现 55.00000000000001');
    expect(applied.last, lessThan(100), reason: '往左拖应该比默认满分低');
  });

  testWidgets('逐项滑块一拖就改这一项（整数分）', (tester) async {
    final hits = <String>[];
    final values = <double>[];
    await tester.pumpWidget(_wrap(onApplyOne: (item, v) {
      hits.add(item.title);
      values.add(v);
    }));

    final itemSliders =
        find.descendant(of: find.byType(ListView), matching: find.byType(Slider));
    expect(itemSliders, findsNWidgets(3), reason: '每一项一条滑块');

    await tester.drag(itemSliders.first, const Offset(-40, 0));
    await tester.pumpAndSettle();

    expect(hits, isNotEmpty);
    expect(hits.toSet(), {'教学态度认真'}, reason: '只动被拖的那一项');
    expect(values.every((v) => v == v.roundToDouble()), isTrue);
  });

  testWidgets('一项都没识别到：给出原因并可重新识别', (tester) async {
    var rescanned = 0;
    await tester.pumpWidget(_wrap(
      state: const EvaluatePanelState(items: [], hint: '没识别到评分项（单选组 0 个）'),
      onRescan: () => rescanned++,
    ));

    expect(find.text('没识别到评分项（单选组 0 个）'), findsOneWidget);
    await tester.tap(find.text('重新识别'));
    await tester.pumpAndSettle();
    expect(rescanned, 1);
  });

  testWidgets('页面是教务登录页：提示先登录并能跳去登录', (tester) async {
    var login = 0;
    await tester.pumpWidget(_wrap(
      state: const EvaluatePanelState(items: _items, login: true),
      onLogin: () => login++,
    ));

    expect(find.text('当前是教务登录页：先登录，再回到评教页识别'), findsOneWidget);
    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();
    expect(login, 1);
  });

  testWidgets('等召回执时滑块照旧能拖（应用是连续的，不因回执禁用）', (tester) async {
    var called = 0;
    await tester.pumpWidget(_wrap(
      state: const EvaluatePanelState(items: _items, busy: true),
      onApplyAll: (_) => called++,
    ));

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.drag(find.byType(Slider).first, const Offset(-60, 0));
    // 进度条一直在动，pumpAndSettle 永远等不到静止
    await tester.pump();
    expect(called, greaterThan(0));
  });
}
