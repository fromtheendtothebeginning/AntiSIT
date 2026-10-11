import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_appearance/plugin_appearance.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:plugin_theme_ink/plugin_theme_ink.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 外观选项都收进这个插件的二级页：主题、深浅色、以及「界面是否实时跟着滑块切换」。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PluginRegistry.I = PluginRegistry(
      features: const [AppearancePlugin()],
      themes: const [GlassTheme(), InkTheme()],
    );
    AppState.I.followSlider = true;
  });

  Future<void> pumpTiles(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Column(
              children: AppearancePlugin().settingsTiles(ctx, PluginRegistry.I)),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('设置里那一条「外观」点进二级页，三样东西都在', (tester) async {
    await pumpTiles(tester);
    expect(find.text('外观'), findsOneWidget);
    // 摘要里带上当前主题与深浅色
    expect(find.textContaining('液态玻璃'), findsOneWidget);

    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();

    expect(find.byType(AppearanceSettingsPage), findsOneWidget);
    expect(find.text('主题'), findsWidgets);
    expect(find.text('液态玻璃'), findsOneWidget, reason: '主题单选在二级页里');
    expect(find.text('墨白极简'), findsOneWidget);
    expect(find.text('夜间模式'), findsOneWidget);
    expect(find.text('界面实时跟着滑块切换'), findsOneWidget);
  });

  testWidgets('二级页里能换主题（单选）', (tester) async {
    await pumpTiles(tester);
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('墨白极简'));
    await tester.pumpAndSettle();
    expect(PluginRegistry.I.theme.id, InkTheme.themeId);
  });

  testWidgets('「界面实时跟着滑块切换」默认开，关掉后会被记住', (tester) async {
    expect(AppState.I.followSlider, isTrue, reason: '默认开');
    await pumpTiles(tester);
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('界面实时跟着滑块切换'));
    await tester.pumpAndSettle();
    expect(AppState.I.followSlider, isFalse);

    await AppState.I.load(); // 重新读本机设置
    expect(AppState.I.followSlider, isFalse, reason: '开关要持久化');
  });

  testWidgets('深浅色滑块拖到中间：整站配色跟着插值（预览值 0..1）', (tester) async {
    addTearDown(() => AppState.I.setAppearancePreview(null));
    await pumpTiles(tester);
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    AppState.I.setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle(); // 等滑块弹到「浅色」再拖，否则从半路起手算出来的亮度是 0

    // 拖「浅色 → 深色」的滑块（y 取深浅色那一行的中心）
    final y = tester.getCenter(find.text('浅色')).dy;
    final g = await tester.startGesture(Offset(300, y));
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
    }
    expect(AppState.I.appearancePreviewDark, isNotNull, reason: '拖动中有预览值');
    expect(AppState.I.appearancePreviewDark, greaterThan(0));
    await g.up();
    await tester.pumpAndSettle();
  });
}
