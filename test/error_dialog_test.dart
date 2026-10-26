import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归用例：组件失败时弹窗要展示学校 / 服务器返回的完整原因，而不是一闪而过的 SnackBar。
void main() {
  testWidgets('showErr 弹窗展示完整原因并可关闭', (tester) async {
    const reason = '用户名或密码不正确，请重新输入！';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showErr(ctx, ApiError(reason), title: '报名失败'),
              child: const Text('触发'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('触发'));
    await tester.pumpAndSettle();
    expect(find.text('报名失败'), findsOneWidget);
    expect(find.text(reason), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text(reason), findsNothing);
  });
}
