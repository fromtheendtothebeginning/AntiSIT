import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可整理宫格的验收：
/// * 4 列基础网格：默认 2x3 = 半屏宽 × 128 高，1x1 = 一格宽 × 一格高；
/// * 长按卡片进入整理并选中它，可拖动换位（顺序回调、没有误触发点击）；
/// * 整理态里点另一张卡会切选中，只有选中的卡显示右下角缩放弧线；
/// * 拖右下角弧线，尺寸吸附到 1x1 / 1x3 / 2x3 / 2x2；
/// * 点空白处退出整理；
/// * 1x1 / 1x3 / 2x2 下卡片内容不溢出（四种尺寸的排版都画得下）。
class _Harness extends StatefulWidget {
  const _Harness({super.key});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final List<String> order = ['a', 'b', 'c'];
  final Map<String, GridCardSize> sizes = {
    'a': GridCardSize.standard,
    'b': GridCardSize.standard,
    'c': GridCardSize.standard,
  };
  bool editing = false;
  String? selectedId;

  /// 测试里外部改尺寸：走 setState 才会重建（State.setState 在 State 外不能直接用）。
  void applySizes(Map<String, GridCardSize> values) {
    setState(() => sizes.addAll(values));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            FlexibleCardGrid(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              items: [
                for (final id in order)
                  FlexibleGridItem(
                    id: id,
                    size: sizes[id]!,
                    builder: (context, size, editing) => Container(
                      color: const Color(0x11000000),
                      alignment: Alignment.center,
                      child: Text('card-$id-${size.key}'),
                    ),
                  ),
              ],
              editing: editing,
              selectedId: selectedId,
              onSelected: (id) => setState(() => selectedId = id),
              onEditingChanged: (value) => setState(() {
                editing = value;
                if (!value) selectedId = null;
              }),
              onOrderChanged: (ids) => setState(
                () => order
                  ..clear()
                  ..addAll(ids),
              ),
              onSizeChanged: (id, size) => setState(() => sizes[id] = size),
            ),
          ],
        ),
      ),
    );
  }
}

/// 长列表：验证拖动到屏幕上下边缘会自动滚动。
class _LongHarness extends StatefulWidget {
  const _LongHarness({super.key});

  @override
  State<_LongHarness> createState() => _LongHarnessState();
}

class _LongHarnessState extends State<_LongHarness> {
  final ScrollController controller = ScrollController();
  final List<String> order = [for (var i = 0; i < 16; i++) 'i$i'];
  bool editing = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ListView(
          controller: controller,
          children: [
            FlexibleCardGrid(
              padding: const EdgeInsets.all(10),
              items: [
                for (final id in order)
                  FlexibleGridItem(
                    id: id,
                    size: GridCardSize.standard,
                    builder: (_, size, editing) => Container(
                      color: const Color(0x11000000),
                      alignment: Alignment.center,
                      child: Text('card-$id'),
                    ),
                  ),
              ],
              editing: editing,
              onEditingChanged: (value) => setState(() => editing = value),
              onOrderChanged: (ids) => setState(
                () => order
                  ..clear()
                  ..addAll(ids),
              ),
              onSizeChanged: (_, __) {},
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  Future<GlobalKey<_HarnessState>> pumpGrid(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key));
    await tester.pumpAndSettle();
    return key;
  }

  Finder card(String id) => find.byKey(ValueKey<String>('fgrid:$id'));
  Finder handle(String id) => find.byKey(ValueKey<String>('fgrid-handle:$id'));

  testWidgets('默认 2x3：6 列基础网格上占 2 行 × 3 列（半屏宽 × 128 高）', (tester) async {
    await pumpGrid(tester);
    // 400 - 20 内边距 - 5×10 间距 = 330 → 每列 55；3 列 = 185，高 2×59 + 10 = 128
    expect(tester.getTopLeft(card('a')), const Offset(10, 10));
    expect(tester.getSize(card('a')), const Size(185, 128));
    expect(tester.getTopLeft(card('b')), const Offset(205, 10));
    expect(tester.getTopLeft(card('c')), const Offset(10, 148));
    expect(find.text('card-a-2x3'), findsOneWidget);
  });

  testWidgets('1x1：1 行 1 列的小方格（1/6 屏宽 × 59 高）', (tester) async {
    final key = await pumpGrid(tester);
    key.currentState!.applySizes({'b': GridCardSize.single});
    await tester.pumpAndSettle();
    expect(tester.getSize(card('b')), const Size(55, 59));
    // a 占 3 列，b 缩成 1 列后紧跟其后：x = 10 + 3×65
    expect(tester.getTopLeft(card('b')), const Offset(205, 10));
    expect(find.text('card-b-1x1'), findsOneWidget);
  });

  testWidgets('1x3 横条：1 行 3 列（半屏宽 × 59 高，与 3 个 1x1 同宽）', (tester) async {
    final key = await pumpGrid(tester);
    key.currentState!.applySizes({'b': GridCardSize.wide});
    await tester.pumpAndSettle();
    expect(tester.getSize(card('b')), const Size(185, 59));
    expect(find.text('card-b-1x3'), findsOneWidget);
  });

  testWidgets('2x2 竖卡：2 行 2 列（1/3 屏宽 × 128 高）', (tester) async {
    final key = await pumpGrid(tester);
    key.currentState!.applySizes({'b': GridCardSize.tall});
    await tester.pumpAndSettle();
    expect(tester.getSize(card('b')), const Size(120, 128));
    expect(find.text('card-b-2x2'), findsOneWidget);
  });

  testWidgets('长按卡片进入整理，竖向拖到另一张前面就换位（松手回写顺序）', (tester) async {
    final key = await pumpGrid(tester);
    final state = key.currentState!;

    final gesture = await tester.startGesture(tester.getCenter(card('b')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(state.editing, isTrue, reason: '长按就进整理，不用再点按钮');
    expect(state.selectedId, 'b', reason: '长按的这张自动成为尺寸条作用对象');

    // 先竖向拖动（方向锁 = 换位置），再挪到 a 的左上角附近
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 30));
    final target = tester.getTopLeft(card('a')) + const Offset(10, 10);
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(state.order, ['b', 'a', 'c']);
    expect(
      tester.getTopLeft(card('b')),
      const Offset(10, 10),
      reason: 'b 占了 a 的位置',
    );
    expect(tester.getTopLeft(card('a')), const Offset(205, 10));
    expect(state.editing, isTrue, reason: '松手后还在整理态，可以继续排');
  });

  testWidgets('整理态里横向拖动 = 改尺寸（往右变大、往左变小），不挪位置', (tester) async {
    final key = await pumpGrid(tester);
    final state = key.currentState!;

    // 长按 a，然后纯横向往右滑：方向锁 = 改尺寸
    final gesture = await tester.startGesture(tester.getCenter(card('a')));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 40));
    expect(state.order, ['a', 'b', 'c'], reason: '横向拖动不改顺序');
    await gesture.up();
    await tester.pumpAndSettle();
    // 2x3 已经是最大档，往右不再变
    expect(state.sizes['a'], GridCardSize.standard);

    // 再往左滑：变小一档（按格数顺序 2x3 → 2x2）
    final left = await tester.startGesture(tester.getCenter(card('a')));
    await tester.pump(const Duration(milliseconds: 600));
    await left.moveBy(const Offset(-40, 0));
    await tester.pump(const Duration(milliseconds: 40));
    await left.up();
    await tester.pumpAndSettle();
    expect(state.sizes['a'], GridCardSize.tall, reason: '往左下滑一档到 2×2');
    expect(state.order, ['a', 'b', 'c'], reason: '顺序仍然不变');
  });

  testWidgets('整理态里拖右下角弧线：按拖出来的宽高吸附到四档里最接近的', (tester) async {
    final key = await pumpGrid(tester);
    final state = key.currentState!;

    // 长按后原地松手，进入整理态并选中 a
    final press = await tester.startGesture(tester.getCenter(card('a')));
    await tester.pump(const Duration(milliseconds: 600));
    await press.up();
    await tester.pumpAndSettle();
    expect(state.editing, isTrue);
    expect(state.selectedId, 'a');
    expect(handle('a'), findsOneWidget);

    // 2x3（185×128）往左拖一档：按「大小顺序」缩小 → 2 行 2 列
    await tester.drag(handle('a'), const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(state.sizes['a'], GridCardSize.tall);
    expect(tester.getSize(card('a')), const Size(120, 128));
    expect(find.text('card-a-2x2'), findsOneWidget);

    // 2x2 再往左一档 → 1 行 3 列横条（大小顺序里比 2×2 再小一档）
    await tester.drag(handle('a'), const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(state.sizes['a'], GridCardSize.wide);
    expect(tester.getSize(card('a')), const Size(185, 59));

    // 1x3 再往左一档 → 1 行 1 列的小方格
    await tester.drag(handle('a'), const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(state.sizes['a'], GridCardSize.single);
    expect(tester.getSize(card('a')), const Size(55, 59));
    expect(find.text('card-a-1x1'), findsOneWidget);
    // 1x1 也保留角标：它是「拖一次就放大回去」的手势
    expect(handle('a'), findsOneWidget, reason: '1x1 也能拖角标放大');

    // 1x1 往右一档 → 1x3，再往右 → 2x2，再往右 → 2x3
    await tester.drag(handle('a'), const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(state.sizes['a'], GridCardSize.wide, reason: '1x1 往右一档 = 1 行 3 列横条');
    await tester.drag(handle('a'), const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(state.sizes['a'], GridCardSize.tall, reason: '再往右一档 = 2×2');
    await tester.drag(handle('a'), const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(
      state.sizes['a'],
      GridCardSize.standard,
      reason: '再往右一档 = 2 行 3 列默认卡',
    );
    expect(handle('a'), findsOneWidget);

    // 2x3 往上拖：竖向只改行数 → 1 行 3 列横条
    await tester.drag(handle('a'), const Offset(0, -40));
    await tester.pumpAndSettle();
    expect(state.sizes['a'], GridCardSize.wide);
    expect(tester.getSize(card('a')), const Size(185, 59));
    expect(find.text('card-a-1x3'), findsOneWidget);

    // 1x3 往下拖：回到 2 行
    await tester.drag(handle('a'), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(state.sizes['a'], GridCardSize.standard);
    expect(tester.takeException(), isNull, reason: '四档尺寸下内容都不能溢出');
  });

  testWidgets('点另一张卡切选中；点卡片之间的空白退出整理', (tester) async {
    final key = await pumpGrid(tester);
    final state = key.currentState!;

    final press = await tester.startGesture(tester.getCenter(card('a')));
    await tester.pump(const Duration(milliseconds: 600));
    await press.up();
    await tester.pumpAndSettle();
    expect(state.editing, isTrue);
    expect(handle('a'), findsOneWidget);
    expect(handle('b'), findsNothing, reason: '只有选中的卡片显示缩放弧线');

    await tester.tap(card('b'));
    await tester.pumpAndSettle();
    expect(state.editing, isTrue, reason: '点卡片是切选中，不该退出');
    expect(state.selectedId, 'b');
    expect(handle('b'), findsOneWidget);
    expect(handle('a'), findsNothing);

    // 两张卡之间的竖缝（第一排在 x=195~205）
    await tester.tapAt(const Offset(200, 50));
    await tester.pumpAndSettle();
    expect(state.editing, isFalse);
    expect(handle('b'), findsNothing);
  });

  testWidgets('四种尺寸混排：1x1 / 1x3 / 2x2 都能塞进同一行', (tester) async {
    final key = await pumpGrid(tester);
    final state = key.currentState!;
    state.applySizes({'b': GridCardSize.wide, 'c': GridCardSize.single});
    await tester.pumpAndSettle();
    // a(2x3) 占 3 列 2 行：b(1x3) 放得进第一行剩下的 3 列（x = 10 + 3×65）
    expect(tester.getTopLeft(card('b')), const Offset(205, 10));
    expect(tester.getSize(card('b')), const Size(185, 59));
    // c(1x1)：第一行满（a 3 列 + b 3 列），落到第二行、a 右边的那 3 列空位
    expect(tester.getTopLeft(card('c')), const Offset(205, 79));
    expect(tester.getSize(card('c')), const Size(55, 59));

    // c 变高成 2x2（2 行 2 列）：第二行 b 右边还剩 3 列，正好放得下
    state.applySizes({'c': GridCardSize.tall});
    await tester.pumpAndSettle();
    expect(tester.getSize(card('c')), const Size(120, 128));
    expect(tester.getTopLeft(card('c')), const Offset(205, 79));
    expect(tester.takeException(), isNull);
  });

  testWidgets('拖到列表下边缘会自动滚动，卡片能带到屏幕外', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<_LongHarnessState>();
    await tester.pumpWidget(_LongHarness(key: key));
    await tester.pumpAndSettle();
    final state = key.currentState!;
    expect(state.controller.offset, 0);

    final gesture = await tester.startGesture(tester.getCenter(card('i0')));
    await tester.pump(const Duration(milliseconds: 600));
    // 400x800 的视口，下边缘 72px 内开始自动滚动
    await gesture.moveTo(const Offset(200, 770));
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(state.controller.offset, greaterThan(0), reason: '手指停在边缘时列表要自己滚');
    await gesture.up();
    await tester.pumpAndSettle();

    expect(state.order.last, 'i0', reason: '滚动后卡片落到了最后');
    expect(state.order.first, 'i1');
    expect(tester.takeException(), isNull);
  });
}
