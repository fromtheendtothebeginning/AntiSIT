import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_evaluate/plugin_evaluate.dart';

/// 评分助手面板：统一分数一条滑块 + 逐项一条滑块。面板不碰 WebView，
/// 所有改分都走回调，所以这里能直接把交互钉住。
const _items = [
  EvalItem(
    index: 0,
    label: '教学态度认真',
    kind: 'radio',
    value: 5,
    min: 1,
    max: 5,
    values: [1, 2, 3, 4, 5],
  ),
  EvalItem(
    index: 1,
    label: '内容充实',
    kind: 'radio',
    value: 4,
    min: 1,
    max: 5,
    values: [1, 2, 3, 4, 5],
  ),
  EvalItem(
    index: 2,
    label: '作业适量',
    kind: 'radio',
    value: 3,
    min: 1,
    max: 5,
    values: [1, 2, 3, 4, 5],
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
  testWidgets('统一分数默认取最高分，一键同分把它打到全部项', (tester) async {
    double? applied;
    await tester.pumpWidget(_wrap(onApplyAll: (v) => applied = v));

    expect(find.text('一键同分'), findsOneWidget);
    expect(find.text('一键同分：把 5 分打到这一页全部 3 项'), findsOneWidget,
        reason: '默认取各项最高分');

    await tester.tap(find.text('一键同分'));
    await tester.pumpAndSettle();
    expect(applied, 5);
  });

  testWidgets('拖动统一分数滑块后再一键同分，按拖出来的分值打', (tester) async {
    double? applied;
    await tester.pumpWidget(_wrap(onApplyAll: (v) => applied = v));

    // 统一滑块是最上面那条（逐项的都在 ListView 里）
    final uniform = find.byType(Slider).first;
    await tester.drag(uniform, const Offset(-200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('一键同分'));
    await tester.pumpAndSettle();

    expect(applied, isNotNull);
    expect(applied!, lessThan(5), reason: '往左拖应该比默认满分低');
  });

  testWidgets('逐项滑块只改那一项（松手回调）', (tester) async {
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

    expect(hits, ['教学态度认真']);
    expect(values.single, lessThanOrEqualTo(5));
    expect(values.single, greaterThanOrEqualTo(1));
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

  testWidgets('等页面回执时按钮禁用，不会连点出一串改分', (tester) async {
    var called = 0;
    await tester.pumpWidget(_wrap(
      state: const EvaluatePanelState(items: _items, busy: true),
      onApplyAll: (_) => called++,
    ));

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '一键同分'));
    expect(button.onPressed, isNull);
    await tester.tap(find.text('一键同分'), warnIfMissed: false);
    // 进度条一直在动，pumpAndSettle 永远等不到静止
    await tester.pump();
    expect(called, 0);
  });
}
