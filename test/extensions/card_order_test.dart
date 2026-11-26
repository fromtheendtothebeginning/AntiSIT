import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpExtensionEnv();

  group('自定义排序', () {
    ExtensionItem item(String id, String name) =>
        ExtensionItem(id: id, name: name, url: 'https://$id.example.com');

    test('排过的按存的顺序在前，没排过的接在后面；重开还生效，恢复默认回原序', () async {
      final store = ExtensionStore.I;
      await store.load();
      for (final (id, name) in [('a', '甲'), ('b', '乙'), ('c', '丙')]) {
        await store.add(item(id, name));
      }
      expect(
        [for (final e in store.items) e.id],
        ['a', 'b', 'c'],
        reason: '默认按添加先后',
      );

      await store.setOrder(['c', 'a', 'b']);
      expect([for (final e in store.items) e.id], ['c', 'a', 'b']);

      await store.add(item('d', '丁'));
      expect(
        [for (final e in store.items) e.id],
        ['c', 'a', 'b', 'd'],
        reason: '新加的排在最后，不动已排好的位置',
      );

      ExtensionStore.I = ExtensionStore(); // 模拟重启
      await ExtensionStore.I.load();
      expect(
        [for (final e in ExtensionStore.I.items) e.id],
        ['c', 'a', 'b', 'd'],
        reason: '排序落在本地',
      );

      await ExtensionStore.I.setOrder(const []);
      expect(
        [for (final e in ExtensionStore.I.items) e.id],
        ['a', 'b', 'c', 'd'],
        reason: '恢复默认',
      );
    });

    testWidgets('排序页：标题栏入口可达，恢复默认立刻回原序', (tester) async {
      final store = ExtensionStore.I;
      await store.load();
      await store.add(item('a', '甲'));
      await store.add(item('b', '乙'));
      await store.setOrder(['b', 'a']);
      await pumpPage(tester);

      await tester.tap(find.byTooltip('排序拓展'));
      await tester.pumpAndSettle();
      expect(find.text('拓展排序'), findsOneWidget);
      expect(
        find.byIcon(Icons.drag_handle_rounded),
        findsNWidgets(2),
        reason: '每条一个拖拽手柄',
      );

      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();
      expect([for (final e in store.items) e.id], ['a', 'b']);
    });

    testWidgets('只有一条拓展时不给排序入口（没得排）', (tester) async {
      await ExtensionStore.I.add(item('a', '甲'));
      await pumpPage(tester);
      expect(find.byTooltip('排序拓展'), findsNothing);
      expect(find.byTooltip('添加拓展'), findsOneWidget, reason: '其它入口照旧');
    });
  });
}

