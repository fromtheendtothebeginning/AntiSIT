import 'package:campus_service/pages/boot_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 启动动画：三层 logo 依次合拢成整体，然后呼吸 + 光环；阶段文案跟着启动流程换。
void main() {
  testWidgets('首帧显示 logo 三层与阶段文案', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BootSplash(stage: '正在读取设置…')),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(BootSplash), findsOneWidget);
    expect(find.text('AntiSIT'), findsOneWidget);
    expect(find.text('正在读取设置…'), findsOneWidget);
    // 浅蓝 / 深蓝 / 绿三层都在（叠回去才是完整的 logo）
    expect(find.byType(Image), findsNWidgets(3));
    final assets = tester
        .widgetList<Image>(find.byType(Image))
        .map((w) => (w.image as AssetImage).assetName)
        .toSet();
    expect(assets, {
      'assets/sit-mark-light.png',
      'assets/sit-mark-dark.png',
      'assets/sit-mark-green.png',
    });
  });

  testWidgets('装配动画在动：连续两帧的 logo 底板尺寸不同', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BootSplash(stage: '正在加载插件…')),
    ));
    await tester.pump(const Duration(milliseconds: 120));
    final a = tester.getRect(find.byKey(const ValueKey('boot-plate')));
    await tester.pump(const Duration(milliseconds: 120));
    final b = tester.getRect(find.byKey(const ValueKey('boot-plate')));
    // 底板是普通 Container：不依赖图片解码，尺寸一定量得到
    expect(a.width, isNot(0));
    expect(a.width, isNot(b.width), reason: 'logo 在装配缩放');
  });

  testWidgets('装配播完后进入呼吸循环：尺寸继续变化', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BootSplash(stage: '正在读取课表…')),
    ));
    // 走完 1.4s 装配，再进入循环
    await tester.pump(const Duration(milliseconds: 1600));
    final a = tester.getRect(find.byType(Image).first);
    await tester.pump(const Duration(milliseconds: 600));
    final b = tester.getRect(find.byType(Image).first);
    expect(a.width, isNot(b.width), reason: '装配完成后继续呼吸');
  });

  testWidgets('阶段文案换了会跟着变', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BootSplash(stage: '正在读取设置…')),
    ));
    await tester.pump();
    expect(find.text('正在读取设置…'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BootSplash(stage: '正在初始化功能…')),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('正在初始化功能…'), findsOneWidget);
    expect(find.text('正在读取设置…'), findsNothing);
  });
}