import 'dart:ui' as ui;

import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 宫格长高动画期间：新排进来的卡片已经落在最终格位、宫格盒子还没长到那儿。
/// 不裁的话这些卡片会**画到宫格外**，盖住紧跟其后那块内容（拓展页「添加拓展」卡
/// 就这么被压住过，截图里虚线框被最后一行卡片盖掉一半）。
///
/// 这里不看 hit test（溢出的子节点本来就点不到），直接看**像素**：
/// 长高途中「添加拓展」卡所在位置不该出现卡片颜色。
class _Grow extends StatefulWidget {
  const _Grow({super.key});

  @override
  State<_Grow> createState() => _GrowState();
}

class _GrowState extends State<_Grow> {
  int count = 4;

  void grow() => setState(() => count = 6);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: FlexibleCardGrid(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                items: [
                  for (var i = 0; i < count; i++)
                    FlexibleGridItem(
                      id: 'c$i',
                      size: i < 2 ? GridCardSize.wide : GridCardSize.tall,
                      builder: (context, s, editing) => Container(
                        color: const Color(0xFF3366FF),
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
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 40),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  key: ValueKey('add-card'),
                  height: 56,
                  child: Center(child: Text('添加拓展')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 取一张图里某个点的颜色（逻辑坐标 → 像素坐标）。
Future<Color> pixelAt(WidgetTester tester, GlobalKey key, Offset point) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final color = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = image.width;
    final x = point.dx.floor();
    final y = point.dy.floor();
    final i = (y * w + x) * 4;
    final bytes = data!.buffer.asUint8List();
    image.dispose();
    return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
  });
  return color!;
}

void main() {
  testWidgets('长高动画期间不把卡片画到「添加拓展」上', (tester) async {
    tester.view.physicalSize = const Size(880, 1904);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final rootKey = GlobalKey();
    final growKey = GlobalKey<_GrowState>();
    await tester.pumpWidget(
      RepaintBoundary(
        key: rootKey,
        child: _Grow(key: growKey),
      ),
    );
    await tester.pumpAndSettle();

    growKey.currentState!.grow();
    // 停在长高一半的位置：新行已就位、盒子还短着
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final add = tester.getRect(find.byKey(const ValueKey('add-card')));
    final probes = <String, Color>{};
    for (final dy in [2.0, 8.0, 16.0, 24.0, 32.0, 44.0]) {
      probes['y+${dy.toInt()}'] = await pixelAt(
        tester,
        rootKey,
        Offset(add.left + 60, add.top + dy),
      );
    }
    expect(
      probes.values,
      everyElement(isNot(const Color(0xFF3366FF))),
      reason: '长高途中「添加拓展」卡的上半截被溢出的卡片盖住了：$probes',
    );
  });
}
