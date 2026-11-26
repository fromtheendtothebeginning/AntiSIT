import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 整理态缩放手势的两个回归：
/// 1. 系统取消（onPanCancel）必须**回滚**，不能当正常松手把尺寸改掉；
/// 2. 角标上按住不动（超过长按阈值）再拖，仍应是缩放，不能被外层「长按拖动卡片」抢走。
void main() {
  Future<void> pumpGrid(
    WidgetTester tester, {
    required List<String> changed,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            FlexibleCardGrid(
              padding: const EdgeInsets.all(10),
              items: [
                for (final id in ['a', 'b', 'c'])
                  FlexibleGridItem(
                    id: id,
                    size: GridCardSize.standard,
                    builder: (context, size, editing) => Container(
                      color: const Color(0x11000000),
                      alignment: Alignment.center,
                      child: Text('card-$id-${size.key}'),
                    ),
                  ),
              ],
              editing: true,
              selectedId: null,
              onSelected: (_) {},
              onEditingChanged: (_) {},
              onOrderChanged: (_) {},
              onSizeChanged: (id, size) => changed.add('$id:${size.key}'),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder handle(String id) => find.byKey(ValueKey<String>('fgrid-handle:$id'));

  testWidgets('角标上按住超过长按阈值再拖：仍然进入缩放', (tester) async {
    final changed = <String>[];
    await pumpGrid(tester, changed: changed);

    expect(handle('a'), findsOneWidget);
    final start = tester.getCenter(handle('a'));

    // 按住 700ms 不动（超过 500ms 长按阈值），再往左上缩：旧实现这里被外层
    // 长按识别器赢走变成「拖动卡片」，尺寸一点都不变。
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(-24, -18));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();

    expect(changed, isNotEmpty, reason: '角标上的长按 + 拖动应当是缩放');
  });

  testWidgets('缩放手势被系统取消：尺寸不变（回滚，不当确认）', (tester) async {
    final changed = <String>[];
    await pumpGrid(tester, changed: changed);

    final start = tester.getCenter(handle('a'));
    final g = await tester.startGesture(start);
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(60, 45));
      await tester.pump();
    }
    // 系统抢走手势（来电 / 通知下拉 / 父级竞技场）：onPanCancel
    await g.cancel();
    await tester.pumpAndSettle();

    expect(changed, isEmpty, reason: '取消不是确认，尺寸不能变');
  });
}
