import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 拓展页真实结构：CustomScrollView → 宫格 sliver → 「添加拓展」sliver。
/// 卡片是分两批到的（内置先到、市场装的异步 load 完再到），高度必须跟着长。
void main() {
  final items = [
    ('a', GridCardSize.standard),
    ('b', GridCardSize.standard),
    ('c', GridCardSize.wide),
    ('d', GridCardSize.wide),
    ('e', GridCardSize.standard),
    ('f', GridCardSize.standard),
    ('g', GridCardSize.standard),
    ('h', GridCardSize.standard),
  ];

  Widget build(List<(String, GridCardSize)> shown) => MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: FlexibleCardGrid(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              items: [
                for (final (id, size) in shown)
                  FlexibleGridItem(
                    id: id,
                    size: size,
                    builder: (context, s, editing) => Container(
                      key: ValueKey('card-$id'),
                      color: const Color(0x22000000),
                      alignment: Alignment.center,
                      child: Text('card-$id'),
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
              child: Container(
                key: const ValueKey('add-card'),
                height: 56,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x55ff0000)),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void check(WidgetTester tester, String when) {
    final add = tester.getRect(find.byKey(const ValueKey('add-card')));
    final bad = <String>[];
    for (final (id, _) in items) {
      final f = find.byKey(ValueKey('card-$id'));
      if (f.evaluate().isEmpty) continue;
      final r = tester.getRect(f);
      if (r.bottom > add.top + 0.5) {
        bad.add('card-$id 下沿 ${r.bottom} > 添加卡上沿 ${add.top}');
      }
    }
    expect(bad, isEmpty, reason: '$when：${bad.join('; ')}');
  }

  setUp(() {});
  tearDown(() {});

  testWidgets('一次给全 8 张', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(build(items));
    await tester.pumpAndSettle();
    check(tester, '一次给全');
  });

  testWidgets('先 4 张，再补到 8 张', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(build(items.take(4).toList()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(build(items));
    await tester.pumpAndSettle();
    check(tester, '补到 8 张');
  });

  testWidgets('先 6 张，再补到 8 张（最贴截图）', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(build(items.take(6).toList()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(build(items));
    await tester.pumpAndSettle();
    check(tester, '补齐');
  });
}
