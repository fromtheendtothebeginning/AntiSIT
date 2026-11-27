import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extensions/harness.dart';

/// 市场页盖在上面时（路由不在最前 → TickerMode 关掉）装完一条，
/// 宫格高度必须已经长到位：否则被 Clip 裁掉的新卡片会「看不见」，
/// 要等下一次有 Ticker 的重建（比如进整理态）才显现。
void main() {
  setUpExtensionEnv();

  testWidgets('盖住时装完：宫格已经长到最终高度，卡片不靠后续动画才出来', (tester) async {
    SharedPreferences.setMockInitialValues({});
    ExtensionStore.I = ExtensionStore();
    for (var i = 0; i < 4; i++) {
      await ExtensionStore.I.add(
        ExtensionItem(
          id: 'e$i',
          name: '拓展 $i',
          url: 'https://h$i.test/p',
          desc: 'd',
          fromMarket: true,
          version: '1.0.0',
        ),
      );
    }
    tester.view.physicalSize = const Size(1080, 2344);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ExtensionsPage()));
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byType(FlexibleCardGrid)).height;

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Center(child: Text('插件市场'))),
    ));
    await tester.pumpAndSettle();

    // 市场页正盖着时装完 3 条（装的人是封住的 Ticker）
    for (var i = 4; i < 7; i++) {
      await ExtensionStore.I.add(
        ExtensionItem(
          id: 'e$i',
          name: '拓展 $i',
          url: 'https://h$i.test/p',
          desc: 'd',
          fromMarket: true,
          version: '1.0.0',
        ),
      );
    }
    await tester.pump();
    final covered = tester
        .getRect(find.byType(FlexibleCardGrid, skipOffstage: false))
        .height;
    nav.pop();
    await tester.pumpAndSettle();
    final after = tester.getRect(find.byType(FlexibleCardGrid)).height;
    // ignore: avoid_print
    print('BEFORE $before COVERED $covered AFTER $after');
    expect(
      covered,
      after,
      reason: '盖着时就该长到位（$covered vs $after），否则新卡片被裁住看不见',
    );
  });
}
