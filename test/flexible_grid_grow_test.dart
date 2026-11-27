import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 同一棵树里卡片从 6 张长到 8 张（拓展页真实场景：内置先到、市场装的 load 完再补）。
/// 宫格高度是 AnimatedSize 慢慢长开的：这段时间里新行卡片已就位、盒子还没长完。
/// 不裁的话它们会画到宫格外、盖住「添加拓展」——按在那儿会点开卡片而不是加号。
class _Grow extends StatefulWidget {
  const _Grow({super.key});

  @override
  State<_Grow> createState() => _GrowState();
}

class _GrowState extends State<_Grow> {
  int count = 6;
  int addTaps = 0;
  int cardTaps = 0;

  void grow() => setState(() => count = 8);

  @override
  Widget build(BuildContext context) {
    const sizes = [
      GridCardSize.standard,
      GridCardSize.standard,
      GridCardSize.wide,
      GridCardSize.wide,
      GridCardSize.standard,
      GridCardSize.standard,
      GridCardSize.standard,
      GridCardSize.standard,
    ];
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: FlexibleCardGrid(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                items: [
                  for (var i = 0; i < count; i++)
                    FlexibleGridItem(
                      id: 'c$i',
                      size: sizes[i],
                      builder: (context, s, editing) => GestureDetector(
                        onTap: () => setState(() => cardTaps++),
                        child: Container(
                          key: ValueKey('card-$i'),
                          color: const Color(0x33000000),
                          alignment: Alignment.center,
                          child: Text('c$i'),
                        ),
                      ),
                    ),
                ],
                editing: false,
                onEditingChanged: (_) {},
                onOrderChanged: (_) {},
                onSizeChanged: (_, __) {},
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
              sliver: SliverToBoxAdapter(
                child: GestureDetector(
                  key: const ValueKey('add-card'),
                  onTap: () => setState(() => addTaps++),
                  child: Container(
                    height: 56,
                    color: const Color(0x33ff0000),
                    alignment: Alignment.center,
                    child: const Text('添加拓展'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('长高动画期间不压住「添加拓展」：那片区域仍然点得到加号', (tester) async {
    tester.view.physicalSize = const Size(880, 1904);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final key = GlobalKey<_GrowState>();
    await tester.pumpWidget(_Grow(key: key));
    await tester.pumpAndSettle();

    key.currentState!.grow();
    // 只推进 30ms：AnimatedSize 正在播，新行卡片已排到最终格位、盒子还短着
    await tester.pump(const Duration(milliseconds: 30));

    final state = key.currentState!;
    final add = tester.getRect(find.byKey(const ValueKey('add-card')));
    // 点添加卡的正中间：若新行卡片溢出盖住这里，点击会被卡片抢走
    await tester.tapAt(add.center);
    await tester.pump();
    expect(state.addTaps, 1, reason: '点添加卡应当触发加号，而不是被溢出的卡片吃掉');
    expect(state.cardTaps, 0);
  });

  testWidgets('长完后仍点得到加号', (tester) async {
    tester.view.physicalSize = const Size(880, 1904);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final key = GlobalKey<_GrowState>();
    await tester.pumpWidget(_Grow(key: key));
    await tester.pumpAndSettle();
    key.currentState!.grow();
    await tester.pumpAndSettle();

    final state = key.currentState!;
    final add = tester.getRect(find.byKey(const ValueKey('add-card')));
    await tester.tapAt(add.center);
    await tester.pump();
    expect(state.addTaps, 1);
    expect(state.cardTaps, 0);
  });
}
