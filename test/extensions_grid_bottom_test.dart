import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';

/// 拓展页的真实结构：CustomScrollView → 宫格 sliver → 「添加拓展」sliver。
/// 卡片数量在首帧之后变多时（市场目录 / 拓展清单异步到位），宫格报的高度必须
/// 跟着变，否则下面那块会画到卡片底下。
void main() {
  testWidgets('首帧只有 4 张，随后变 6 张：宫格高度跟着长，添加卡不压在卡片上', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _Harness(initial: 4),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_overlaps(tester), isEmpty, reason: '首帧 4 张时就不该压');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _Harness(initial: 6),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_overlaps(tester), isEmpty, reason: '变成 6 张后添加卡不该压在最后一行');
  });
}

/// 最后一行卡片的下沿 vs 「添加拓展」的上沿：前者超过后者就算压住了。
List<String> _overlaps(WidgetTester tester) {
  final addCard = tester.getRect(find.byType(ExtensionAddCard));
  final out = <String>[];
  for (var i = 0; i < 6; i++) {
    final f = find.byKey(ValueKey('c$i'));
    if (f.evaluate().isEmpty) continue;
    final r = tester.getRect(f);
    if (r.bottom > addCard.top + 0.5) {
      out.add('卡片 c$i 下沿 ${r.bottom} > 添加卡上沿 ${addCard.top}');
    }
  }
  return out;
}

class _Harness extends StatelessWidget {
  const _Harness({required this.initial});

  final int initial;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: FlexibleCardGrid(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          items: [
            for (var i = 0; i < initial; i++)
              FlexibleGridItem(
                id: 'c$i',
                size: GridCardSize.standard,
                builder: (context, size, editing) => Container(
                  key: ValueKey('c$i'),
                  color: const Color(0x22000000),
                  alignment: Alignment.center,
                  child: Text('c$i'),
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
          child: ExtensionAddCard(onTap: () {}),
        ),
      ),
    ],
  );
}
