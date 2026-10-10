import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 底栏滑块（pill）自身的拖拽：跟手 + 就近落格。
/// 页面区域横滑是另一套（见 home_swipe_test），这里只钉住底栏这一侧。
void main() {
  Future<List<int>> pumpBar(
    WidgetTester tester, {
    ValueNotifier<double?>? dragPos,
    ValueNotifier<double>? position,
  }) async {
    final picked = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: GlassNavBar(
          items: const [
            GlassNavBarItem(Icons.home_outlined, Icons.home, '课程表'),
            GlassNavBarItem(Icons.qr_code, Icons.qr_code, '校园码'),
            GlassNavBarItem(Icons.build_outlined, Icons.build, '工具'),
          ],
          index: 0,
          dragPosition: dragPos,
          position: position,
          onChanged: picked.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('把连续位置写出来：页面靠它跟滑块用同一套弹簧动', (tester) async {
    final pos = ValueNotifier<double>(0);
    addTearDown(pos.dispose);
    final picked = await pumpBar(tester, position: pos);
    expect(pos.value, 0, reason: '初始位置 = 当前格');

    await tester.tap(find.text('校园码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(pos.value, greaterThan(0.05), reason: '弹簧一起步就往外写位置');
    expect(pos.value, lessThan(0.95), reason: '还在路上（写的是连续位置，不是只报终点）');

    await tester.pumpAndSettle();
    expect(pos.value, closeTo(1, 0.01), reason: '最后停在第二格');
    expect(picked, [1]);
  });

  testWidgets('慢拖过一半：落格到第二格并回调', (tester) async {
    final picked = await pumpBar(tester);

    // 滑块是「跟手」的：往右拖 = 去下一格（与页面区域横滑的方向相反，页面那边是翻页直觉）
    await tester.drag(find.text('课程表'), const Offset(200, 0));
    await tester.pumpAndSettle();

    expect(picked, [1], reason: '拖过一半就落到第二格');
  });

  testWidgets('慢拖不到一半：弹回原格，不回调', (tester) async {
    final picked = await pumpBar(tester);

    await tester.drag(find.text('课程表'), const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(picked, isEmpty);
  });

  testWidgets('外壳给的连续位置（页面区域拖动）：滑块按就近高亮，松手交还底栏', (tester) async {
    final dragPos = ValueNotifier<double?>(null);
    addTearDown(dragPos.dispose);
    final picked = await pumpBar(tester, dragPos: dragPos);

    // 1.6 格：滑块停在第二、三格之间，最近的第三格高亮
    dragPos.value = 1.6;
    await tester.pump();
    final third = tester.widget<Icon>(find.byIcon(Icons.build_outlined));
    final first = tester.widget<Icon>(find.byIcon(Icons.home_outlined));
    expect(third.color, SemColors.accent, reason: '最近的格子高亮');
    expect(first.color, SemColors.textMuted, reason: '离开的格子恢复普通色');

    dragPos.value = null; // 松手：落点由外壳决定，底栏只负责滑过去
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
  });
}
