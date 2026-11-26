import 'package:campus_core/campus_core.dart';
import 'package:campus_service/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 预测式返回的前提：Navigator 派发 NavigationNotification → WidgetsApp 调 setFrameworkHandlesBack(true)，引擎才注册返回回调；这里验这条链路真的通。
void main() {
  testWidgets('push 之后会告诉引擎：返回交给 Flutter 处理', (tester) async {
    final backCalls = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (MethodCall call) async {
      if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
        backCalls.add(call.arguments);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(GlassPalette.light),
      // 用 App 自己的 handler（不设生命周期条件）
      onNavigationNotification: onNavigationNotification,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const Scaffold(body: Text('第二页')))),
            child: const Text('push'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 首页不能返回 → 交给系统
    expect(backCalls, contains(false),
        reason: '首页没有再可返回的路由，该由系统处理（此时返回=退出 App）');

    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    // 有可返回的路由了 → 交给 Flutter（引擎据此注册返回手势回调）
    expect(backCalls, contains(true),
        reason: '不告诉引擎的话，系统返回手势会被当成「退出页面/回桌面」，'
            'Dart 侧的 handleStartBackGesture 收不到，预测式动画也就无从谈起');
  });
}
