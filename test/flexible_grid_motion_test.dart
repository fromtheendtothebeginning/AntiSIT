import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_core/campus_core.dart';

/// 邻居卡片「让位」的动画语义：时长不短于 0.2 秒，动画播放期间目标又变时从当前位置接着走（不重播）。
void main() {
  Future<GlobalKey<_HarnessState>> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key));
    await tester.pumpAndSettle();
    return key;
  }

  Finder card(String id) => find.byKey(ValueKey<String>('fgrid:$id'));

  testWidgets('邻居让位动画不短于 0.2 秒', (tester) async {
    final key = await pump(tester);
    final before = tester.getTopLeft(card('b'));

    key.currentState!.resize('a', GridCardSize.single);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.getTopLeft(card('b')),
      isNot(before),
      reason: '100ms 时已经开始动，但还没到位',
    );
    final mid = tester.getTopLeft(card('b'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      tester.getTopLeft(card('b')),
      isNot(mid),
      reason: '160ms 仍在动画中：说明时长 >= 0.2s',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('动画期间目标又变：从当前位置继续，不跳回起点', (tester) async {
    final key = await pump(tester);
    final start = tester.getTopLeft(card('b'));

    // 第一次变化：a 缩成 1x1
    key.currentState!.resize('a', GridCardSize.single);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final firstMid = tester.getTopLeft(card('b'));
    expect(firstMid, isNot(start), reason: '第一段已经在走');

    // 第二段：半路把 a 改成 1x3，b 的目标位置又变了
    key.currentState!.resize('a', GridCardSize.wide);
    await tester.pump();
    final afterRetarget = tester.getTopLeft(card('b'));
    // 关键：改目标那一帧不能跳回起点 start（否则就是「重播」）
    expect(
      afterRetarget,
      isNot(start),
      reason: '改目标时从当前位置接着走，不回到起点',
    );
    expect(
      (afterRetarget - firstMid).distance,
      lessThan(40),
      reason: '改目标那一帧位置基本不变（差项起步，视觉连续）',
    );
    await tester.pumpAndSettle();
  });
}

class _Harness extends StatefulWidget {
  const _Harness({super.key});
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final sizes = <String, GridCardSize>{
    'a': GridCardSize.standard,
    'b': GridCardSize.standard,
    'c': GridCardSize.standard,
  };

  void resize(String id, GridCardSize size) =>
      setState(() => sizes[id] = size);

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          FlexibleCardGrid(
            items: [
              for (final id in ['a', 'b', 'c'])
                FlexibleGridItem(
                  id: id,
                  size: sizes[id]!,
                  builder: (_, __, ___) => const SizedBox(),
                ),
            ],
            editing: false,
            onEditingChanged: (_) {},
            onOrderChanged: (_) {},
            onSizeChanged: (id, s) => setState(() => sizes[id] = s),
          ),
        ],
      ),
    ),
  );
}