import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extensions/harness.dart';

/// 拓展页真实结构（截图里那张）：8 张卡混排 2x3 / 1x3，加上「添加拓展」卡。
/// 添加卡画到卡片底下的 bug 就出在这里 —— 用真页面复现，别只测宫格。
void main() {
  setUpExtensionEnv();

  List<ExtensionItem> items(int count) => [
    for (var i = 0; i < count; i++)
      ExtensionItem(
        id: 'e$i',
        name: '拓展 $i',
        url: 'https://example$i.test/page',
        desc: '说明 $i',
        builtin: true,
        version: '1.0.0',
      ),
  ];

  Future<void> pumpWith(WidgetTester tester, int count) async {
    ExtensionStore.builtins = items(count);
    // 第 2、3 张改成 1x3 横条：截图里 anticlass / anticraft 就是这种矮条
    SharedPreferences.setMockInitialValues({
      'plugin.ext.sizes': '{"e0":"2x3","e1":"2x3","e2":"1x3","e3":"1x3",'
          '"e4":"2x3","e5":"2x3","e6":"2x3","e7":"2x3"}',
    });
    ExtensionStore.I = ExtensionStore();
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ExtensionsPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('8 张混排：添加拓展卡不与最后一行卡片重叠', (tester) async {
    await pumpWith(tester, 8);

    final add = tester.getRect(find.byType(ExtensionAddCard));
    final bad = <String>[];
    for (var i = 0; i < 8; i++) {
      final f = find.text('拓展 $i');
      if (f.evaluate().isEmpty) continue;
      final r = tester.getRect(f);
      if (r.bottom > add.top + 0.5) {
        bad.add('卡片 $i 文字下沿 ${r.bottom} > 添加卡上沿 ${add.top}');
      }
    }
    expect(bad, isEmpty, reason: bad.join('; '));
  });

  testWidgets('4 张（只有两行）：添加卡在卡片下面', (tester) async {
    await pumpWith(tester, 4);
    final add = tester.getRect(find.byType(ExtensionAddCard));
    final bad = <String>[];
    for (var i = 0; i < 4; i++) {
      final r = tester.getRect(find.text('拓展 $i'));
      if (r.bottom > add.top + 0.5) {
        bad.add('卡片 $i 文字下沿 ${r.bottom} > 添加卡上沿 ${add.top}');
      }
    }
    expect(bad, isEmpty, reason: bad.join('; '));
  });
}