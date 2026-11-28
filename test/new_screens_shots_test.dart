import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:campus_core/campus_core.dart';
import 'package:campus_service/main.dart';
import 'package:campus_service/pages/boot_splash.dart';
import 'package:campus_service/pages/update_center_page.dart';
import 'package:campus_service/update_check.dart';
import 'package:campus_service/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_activities/activity_watch_settings_page.dart';
import 'package:plugin_ext/market/ext_dependency_plan.dart';
import 'package:plugin_ext/market/ext_dependency_sheet.dart';
import 'package:plugin_ext/market/market_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 新增界面演示截图（本机手动跑，CI 全程跳过）：
///
///   DEMO_SHOTS=1 flutter test test/new_screens_shots_test.dart
///
/// 产物 build/demo_shots/*.png（390 宽 @3x，文件名 + dark/light 后缀）。
void main() {
  const size = Size(390, 844);
  const pixelRatio = 3.0;
  final enabled = Platform.environment.containsKey('DEMO_SHOTS');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    AppState.I.demo = true;
  });

  tearDown(() => AppState.I.demo = false);

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
    final title = t.appBarTheme.titleTextStyle;
    const fallback = TextStyle(fontFamily: 'Roboto');
    return t.copyWith(
      appBarTheme: t.appBarTheme.copyWith(
        titleTextStyle: title?.copyWith(fontFamily: 'Roboto'),
      ),
      // 弹窗里的标题 / 正文走 Theme 默认样式（没有 family），不补就渲染成 Ahem 方块
      dialogTheme: t.dialogTheme.copyWith(
        titleTextStyle:
            (t.dialogTheme.titleTextStyle ?? fallback)
                .copyWith(fontFamily: 'Roboto'),
        contentTextStyle:
            (t.dialogTheme.contentTextStyle ?? fallback)
                .copyWith(fontFamily: 'Roboto'),
      ),
    );
  }

  /// 拍「启动动画的某一时刻」：不给假时钟推进太多，让装配停在 [ms]。
  Future<void> shootFrames(
      WidgetTester tester, String name, Widget page,
      {required int ms, required GlassPalette palette}) async {
    tester.view.physicalSize =
        Size(size.width * pixelRatio, size.height * pixelRatio);
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);

    SemColors.p = palette;
    final brightness = palette.isDark ? Brightness.dark : Brightness.light;
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
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
          themeMode:
              brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          locale: appLocale,
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          home: page,
        ),
      ),
    ));

    await tester.runAsync(() async {
      for (final asset in const [
        'assets/sit-mark-light.png',
        'assets/sit-mark-dark.png',
        'assets/sit-mark-green.png',
      ]) {
        try {
          await precacheImage(
            AssetImage(asset),
            tester.element(find.byType(MaterialApp)),
          );
        } catch (_) {}
      }
    });
    // 一小步一小步推进，避免一次跳过装配的关键帧
    for (var t = 0; t < ms; t += 40) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    await captureShot(tester, key, name, palette);
    await tester.pumpWidget(const SizedBox());
  }

  /// 拍一整页（含玻璃背景与顶栏）。
  Future<void> shoot(WidgetTester tester, String name, Widget page,
      {required GlassPalette palette, int frames = 4}) async {
    tester.view.physicalSize =
        Size(size.width * pixelRatio, size.height * pixelRatio);
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);

    SemColors.p = palette;
    final brightness = palette.isDark ? Brightness.dark : Brightness.light;
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
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
          themeMode:
              brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          locale: appLocale,
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          builder: (c, child) =>
              GlassBackground(wells: const [], child: child!),
          home: page,
        ),
      ),
    ));

    // 图片解码是真实异步的（假时钟推不动它）：先 precache，截图里才有 logo
    // 图片解码是真实异步的（假时钟推不动它）：先把 logo 三层都 precache 掉
    await tester.runAsync(() async {
      for (final asset in const [
        'assets/sit-mark-light.png',
        'assets/sit-mark-dark.png',
        'assets/sit-mark-green.png',
      ]) {
        try {
          await precacheImage(
            AssetImage(asset),
            tester.element(find.byType(MaterialApp)),
          );
        } catch (_) {}
      }
    });

    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    await captureShot(tester, key, name, palette);
    await tester.pumpWidget(const SizedBox());
  }

  /// 只拍一个部件（弹层 / 面板这类不该带整页背景的）：窗口按 [height] 给，
  /// 部件在里面居中，图里只有它。
  ///
  /// 传 `Widget Function()` 而不是 Widget：配色是 build 时读 [SemColors] 的，
  /// 必须等 palette 设好之后再构造。
  Future<void> shootWidget(
      WidgetTester tester, String name, Widget Function() child,
      {required GlassPalette palette,
      required double width,
      required double height}) async {
    tester.view.physicalSize = Size(width * pixelRatio, height * pixelRatio);
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);

    SemColors.p = palette;
    final brightness = palette.isDark ? Brightness.dark : Brightness.light;
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MediaQuery(
        data: MediaQueryData(size: Size(width, height), padding: EdgeInsets.zero),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: shotTheme(palette),
          themeMode:
              brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          locale: appLocale,
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          home: Scaffold(
            backgroundColor: SemColors.bg,
            body: Center(child: child()),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await captureShot(tester, key, name, palette);
    await tester.pumpWidget(const SizedBox());
  }

  void shots(String name, Widget Function() page, {int frames = 4}) {
    for (final palette in [GlassPalette.dark, GlassPalette.light]) {
      final suffix = palette.isDark ? 'dark' : 'light';
      testWidgets('$name-$suffix', (tester) async {
        await loadFonts();
        await shoot(tester, name, page(), palette: palette, frames: frames);
      }, skip: !enabled);
    }
  }

  // 1) 二课新活动提醒设置页：已开启 + 各选了一个分类
  for (final palette in [GlassPalette.dark, GlassPalette.light]) {
    final suffix = palette.isDark ? 'dark' : 'light';
    testWidgets('activity-watch-$suffix', (tester) async {
      await loadFonts();
      ActivityWatchService.I.rule = const ActivityWatchRule(
        enabled: true,
        dl: {'思想成长'},
        lb: {'讲座报告'},
      );
      await shoot(tester, 'activity-watch', const ActivityWatchSettingsPage(),
          palette: palette);
    }, skip: !enabled);
  }

  // 2) 拓展依赖树下载界面：应用插件 + 两层依赖，一个已装、一个下载中
  for (final palette in [GlassPalette.dark, GlassPalette.light]) {
    final suffix = palette.isDark ? 'dark' : 'light';
    testWidgets('ext-dependency-$suffix', (tester) async {
      await loadFonts();
      await shootWidget(tester, 'ext-dependency', dependencyPanel,
          palette: palette, width: size.width, height: 430);
    }, skip: !enabled);
  }

  // 3) 启动动画：装配完成后的一帧（logo三层合成 + 呼吸光环）
  shots('boot-splash', () => const Scaffold(
        body: BootSplash(stage: '正在加载课程表…'),
      ), frames: 4);

  // 3b) 装配过程：同一页面在几个时刻各拍一张，拼成「分层合拢」的顺序
  for (final (i, ms) in const [
    (0, 330),
    (1, 500),
    (2, 760),
    (3, 1150),
  ]) {
    testWidgets('boot-assemble-0$i', (tester) async {
      await loadFonts();
      await shootFrames(tester, 'boot-assemble-0$i',
          const Scaffold(body: BootSplash(stage: '正在加载课程表…')),
          ms: ms, palette: GlassPalette.dark);
    }, skip: !enabled);
  }

  // 4) 检查更新二级页：稳定版与内测版各自有新版本（注入假 Release，不联网）
  for (final palette in [GlassPalette.dark, GlassPalette.light]) {
    final suffix = palette.isDark ? 'dark' : 'light';
    testWidgets('update-center-$suffix', (tester) async {
      await loadFonts();
      UpdateChecker.I.reset();
      UpdateChecker.I.current = '1.47.4';
      UpdateChecker.I.debugFetch = () async => [
        {
          'tag_name': 'v1.48.0',
          'html_url': 'https://github.com/fromtheendtothebeginning/AntiSIT/releases/tag/v1.48.0',
          'body': '### 本次更新\n- 检查更新改成二级页面',
          'assets': const [],
        },
        {
          'tag_name': 'v1.49.0-dev.1',
          'html_url': 'https://github.com/fromtheendtothebeginning/AntiSIT/releases/tag/v1.49.0-dev.1',
          'body': '### 本次更新\n- 内测版新功能',
          'assets': const [],
        },
      ];
      await shoot(tester, 'update-center',
          const UpdateCenterPage(autoPrompt: false),
          palette: palette, frames: 5);
    }, skip: !enabled);
  }

  // 5) 稳定版有新版本时的弹窗（真组件）
  for (final palette in [GlassPalette.dark, GlassPalette.light]) {
    final suffix = palette.isDark ? 'dark' : 'light';
    testWidgets('update-dialog-$suffix', (tester) async {
      await loadFonts();
      UpdateChecker.I.reset();
      UpdateChecker.I.current = '1.47.4';
      UpdateChecker.I.debugFetch = () async => [
        {
          'tag_name': 'v1.48.0',
          'html_url': 'https://github.com/fromtheendtothebeginning/AntiSIT/releases/tag/v1.48.0',
          'body': '### 本次更新\n'
              '- 检查更新改成二级页面：稳定版与内测版分开显示，可切换渠道\n'
              '- 第二课堂新活动可以后台提醒（每小时检查一次）\n'
              '- 插件改成一个插件一个文件夹\n'
              '- 拓展插件支持依赖树：装应用插件自动补依赖\n'
              '- 冷启动播放启动动画，课表与插件后台异步加载',
          'assets': const [],
        },
      ];
      await UpdateChecker.I.check();
      await shoot(tester, 'update-dialog', updateDialogShot(),
          palette: palette, frames: 5);
    }, skip: !enabled);
  }
}

/// 稳定版有新版本时的弹窗：走真实的 [showUpdateDialog]，进页面后自动弹出。
Widget updateDialogShot() => const _UpdateDialogShot();

class _UpdateDialogShot extends StatefulWidget {
  const _UpdateDialogShot();

  @override
  State<_UpdateDialogShot> createState() => _UpdateDialogShotState();
}

class _UpdateDialogShotState extends State<_UpdateDialogShot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final info = UpdateChecker.I.stableLatest;
      if (mounted && info != null) showUpdateDialog(context, info);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Colors.transparent,
    body: SizedBox(),
  );
}

/// 把 [key] 包住的那棵子树写成 PNG（build/demo_shots/<名字>-<配色>.png）。
Future<void> captureShot(WidgetTester tester, GlobalKey key, String name,
    GlassPalette palette) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!;
  });
  final dir = Directory('build/demo_shots')..createSync(recursive: true);
  final suffix = palette.isDark ? 'dark' : 'light';
  final file = File('${dir.path}/$name-$suffix.png')
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
  debugPrint('shot ${file.path}');
}

/// 依赖树面板本体（不含整页背景）。
Widget dependencyPanel() {
  MarketEntry entry(String id, String name,
          {String role = 'application', List<Object?> requires = const []}) =>
      MarketEntry(
        id: id,
        name: name,
        desc: '',
        author: '',
        category: '工具',
        icon: '',
        type: 'bundle',
        version: '1.0.0',
        url: '',
        homepage: '',
        zip: 'pkg/$id.zip',
        sha256: 'h' * 32,
        size: 1024,
        permissions: const [],
        minAppVersion: '',
        runtime: 'cordis',
        role: role,
        requires: requires,
      );
  final catalog = <String, MarketEntry>{
    'sit.attendance':
        entry('sit.attendance', '上课打卡助手', requires: ['sit.lib-core']),
    'sit.lib-core': entry('sit.lib-core', '核心接口库',
        role: 'dependency', requires: ['sit.lib-util']),
    'sit.lib-util': entry('sit.lib-util', '通用工具库', role: 'dependency'),
  };
  final nodes = {
    for (final e in catalog.values) e.id: parseExtNodes([e]).single,
  };
  const installed = {'sit.lib-util': '1.0.0'};
  final plan = planExtInstall(
    target: nodes['sit.attendance']!,
    catalog: nodes,
    installed: installed,
  );
  // 演示「下载中」：核心接口库正在进行
  final rows = [
    for (final r in extTreeRows(plan, installed: installed))
      if (r.node.id == 'sit.lib-core')
        r.copyWith(state: ExtTreeState.downloading)
      else
        r,
  ];
  return Material(
    color: SemColors.menuBg,
    borderRadius: BorderRadius.circular(28),
    clipBehavior: Clip.antiAlias,
    child: ExtDependencyDownloadSheet(
      rows: rows,
      // 永不完成：截图停在「正在安装插件」的进行中状态
      run: (onStep) => Completer<void>().future,
    ),
  );
}