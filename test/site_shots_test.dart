import 'dart:io';
import 'dart:ui' as ui;

import 'package:campus_core/campus_core.dart';
import 'package:campus_service/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_academic/plugin_academic.dart';
import 'package:plugin_activities/plugin_activities.dart';
import 'package:plugin_ecard/plugin_ecard.dart';
import 'package:plugin_electricity/plugin_electricity.dart';
import 'package:plugin_evaluate/plugin_evaluate.dart';
import 'package:plugin_exams/plugin_exams.dart';
import 'package:plugin_ext/plugin_ext.dart';
import 'package:plugin_grades/plugin_grades.dart';
import 'package:plugin_score/plugin_score.dart';
import 'package:plugin_theme_glass/plugin_theme_glass.dart';
import 'package:plugin_timetable/plugin_timetable.dart';
import 'package:plugin_tools/plugin_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 官网截图生成器（**本机手动跑，CI 全程跳过**）：
///
///   SITE_SHOTS=1 flutter test test/site_shots_test.dart
///
/// 产物 build/site_shots/ 下的 PNG（390×844 @3x，页面名 + dark/light 后缀）：
/// * 数据走演示假数据，但**不渲染 App 的演示模式界面** —— 只画单页，没有底部「演示模式」横幅；
/// * 配色取 App 当前源码的两套色板（深色 = 官网默认的「夜航玻璃」，浅色 = 「晨光玻璃」），
///   官网按访客主题二选一显示，所以截图颜色永远跟着网站走；
/// * 内容永远来自当前源码，不是历史存档图。
void main() {
  const size = Size(390, 844);
  const pixelRatio = 3.0;
  final enabled = Platform.environment.containsKey('SITE_SHOTS');

  const wakelockToggle =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    AppState.I.demo = true;
    PluginRegistry.I = PluginRegistry(
      // 注册全部功能插件：工具页的图标宫格才有完整内容
      features: const [
        TimetablePlugin(),
        EcardPlugin(),
        ToolsPlugin(),
        GradesPlugin(),
        ExamsPlugin(),
        ScorePlugin(),
        AcademicPlugin(),
        ActivitiesPlugin(),
        ElectricityPlugin(),
        EvaluatePlugin(),
        ExtPlugin(),
      ],
      themes: const [GlassTheme()],
    );
  });

  tearDown(() {
    AppState.I.demo = false;
  });

  /// 测试环境默认字体是 Ahem（全是方块）：中文挂到 Roboto，图标挂到 MaterialIcons。
  Future<void> loadFonts() async {
    Future<void> add(String family, String path) async {
      final f = File(path);
      if (!f.existsSync()) return;
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      await loader.load();
    }

    await add('Roboto', r'C:\Windows\Fonts\NotoSansSC-VF.ttf');
    await add(
        'MaterialIcons',
        r'D:\app\Flutter\flutter_windows_3.35.7-stable\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf');
  }

  ThemeData shotTheme(GlassPalette p) {
    final t = buildAppTheme(p);
    // 顶栏标题是显式 TextStyle（没有 family），测试里会掉回 Ahem → 方块
    final title = t.appBarTheme.titleTextStyle;
    return t.copyWith(
      appBarTheme: t.appBarTheme.copyWith(
        titleTextStyle: title?.copyWith(fontFamily: 'Roboto'),
      ),
    );
  }

  Future<void> shoot(WidgetTester tester, String name, Widget page,
      {required GlassPalette palette, int extraMs = 0, bool demo = true}) async {
    AppState.I.demo = demo;
    tester.view.physicalSize = Size(size.width * pixelRatio, size.height * pixelRatio);
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(wakelockToggle,
        (ByteData? _) async => const StandardMessageCodec().encodeMessage(<Object?>[null]));

    SemColors.p = palette;
    final brightness = palette.isDark ? Brightness.dark : Brightness.light;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MediaQuery(
          data: const MediaQueryData(
            size: size,
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
          ),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: shotTheme(palette),
            themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
            locale: appLocale,
            supportedLocales: appSupportedLocales,
            localizationsDelegates: appLocalizationsDelegates,
            builder: (c, child) => GlassBackground(wells: const [], child: child!),
            home: page,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 900));
    }
    if (extraMs > 0) {
      await tester.pump(Duration(milliseconds: extraMs));
      await tester.pump(const Duration(milliseconds: 600));
    }

    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!;
    });
    final dir = Directory('build/site_shots')..createSync(recursive: true);
    final suffix = palette.isDark ? 'dark' : 'light';
    File('${dir.path}/$name-$suffix.png').writeAsBytesSync(bytes!.buffer.asUint8List());

    // 收尾：换掉整棵树，并把演示数据的异步延时清干净（否则报「Timer 还挂着」）
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  void shots(String name, Widget Function() page,
      {int extraMs = 0, bool demo = true}) {
    for (final palette in [GlassPalette.dark, GlassPalette.light]) {
      final suffix = palette.isDark ? 'dark' : 'light';
      testWidgets('$name-$suffix', (tester) async {
        await loadFonts();
        await shoot(tester, name, page(),
            palette: palette, extraMs: extraMs, demo: demo);
      }, skip: !enabled);
    }
  }

  shots('timetable', () => const TimetablePage());
  shots('ecard', () => const EcardPage(), extraMs: 1200);
  shots('grades', () => const GradesPage());
  shots('activities', () => const ActivitiesPage());
  // 拓展页不种演示数据：官网展示不想出现「演示记事本」这种假卡片
  shots('extensions', () => const ExtensionsPage(), extraMs: 800, demo: false);
  shots('tools', () => const ToolsPage(), extraMs: 800);
}