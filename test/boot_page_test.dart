import 'package:campus_service/pages/boot_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 启动动画：首帧就能看到校徽、光环与阶段文案；动画真的在动。
void main() {
  testWidgets('首帧显示校徽与阶段文案', (tester) async {
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
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('动画在动：连续两帧的校徽尺寸不同', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BootSplash(stage: '正在加载插件…')),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    final a = tester.getRect(find.byType(Image).first);
    await tester.pump(const Duration(milliseconds: 400));
    final b = tester.getRect(find.byType(Image).first);
    expect(a.width, isNot(b.width), reason: '校徽在呼吸缩放');
  });
}
