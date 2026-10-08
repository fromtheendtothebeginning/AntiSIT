import 'package:campus_service/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 校园码底板（二维码背后那块）必须**只在深色主题下**是白底：
/// 浅色主题画白底的话，玻璃卡上会露出一块白色方块（用户报过的「白色正方形」）；
/// 深色主题不垫白底则深色模块无法辨认、扫不出来。
void main() {
  Future<BoxDecoration> plateDecoration(WidgetTester tester, Brightness brightness) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: const Scaffold(body: Center(child: QrPlate(child: SizedBox.shrink()))),
    ));
    await tester.pump();

    final plate = find.byType(QrPlate);
    expect(plate, findsOneWidget);
    final container = find.descendant(of: plate, matching: find.byType(Container)).first;
    return tester.widget<Container>(container).decoration! as BoxDecoration;
  }

  testWidgets('浅色主题：底板不画白底', (tester) async {
    final deco = await plateDecoration(tester, Brightness.light);
    expect(deco.color, isNull, reason: '浅色主题下不该有白色底——那正是用户看到的白方块');
    expect(deco.borderRadius, isNotNull, reason: '仍要圆角裁剪：旧服务端的白底图也只露圆角');
  });

  testWidgets('深色主题：底板垫白底', (tester) async {
    final deco = await plateDecoration(tester, Brightness.dark);
    expect(deco.color, Colors.white, reason: '深色卡面上必须垫亮底，否则扫不出来');
    expect(deco.borderRadius, isNotNull);
  });
}
