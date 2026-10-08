import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'class_reminder_service.dart';
import 'direct/mock_campus_server.dart';
import 'pages/home_page.dart';
import 'widgets/captcha_dialog.dart';
import 'widgets/common.dart';

/// 中文：日期/时间选择器、长按菜单等 Material 内置文案默认是英文，必须挂这些 delegates。
/// 抽成常量便于单测直接复用（测试里自己搭 MaterialApp 时也要挂同一份）。
const appLocale = Locale('zh');
const appSupportedLocales = <Locale>[Locale('zh'), Locale('en')];
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// fade-through 页面过渡：旧页在前 35% 快速淡出，新页在其后淡入；
/// 被覆盖页不做位移缩放，玻璃透明面不会互相叠影。
class _FadeThroughTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeThroughTransitionsBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    return FadeTransition(
      // 本页被新页覆盖时（secondary 0→1）快速淡出；在上层时不衰减
      opacity: Tween<double>(begin: 1, end: 0).animate(CurvedAnimation(
          parent: secondaryAnimation,
          curve: const Interval(0, 0.35, curve: Curves.easeIn))),
      child: FadeTransition(
        // 本页作为新页进入时快速淡入；返回时对称淡出
        opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0.15, 0.65, curve: Curves.easeOut)),
        child: child,
      ),
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 竖屏锁定：手机横过来也不跟着陀螺仪转（页面布局按竖屏设计）
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // 直连模式的学校系统验证码输入弹窗（服务器模式用不到）
  installDirectCaptchaPrompt();
  runApp(const CampusApp());
}

/// 液态玻璃主题（参照 anticlass「夜航玻璃拟态」）：透明 Scaffold + 全局场景底 +
/// 半透明玻璃面。玻璃无色、颜色属于场景，全部取值来自 [palette]。
ThemeData buildGlassTheme(GlassPalette c) {
  final scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: c.isDark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: c.accent,
    secondary: c.gold,
    error: c.danger,
    surface: c.isDark ? const Color(0xFF16233A) : Colors.white,
    onSurface: c.textPrimary,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent, // 透出全局玻璃场景底
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: true,
      foregroundColor: c.textPrimary,
      iconTheme: IconThemeData(color: c.textPrimary),
      systemOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness: c.isDark ? Brightness.light : Brightness.dark),
    ),
    iconTheme: IconThemeData(color: c.textPrimary),
    cardTheme: CardThemeData(
      elevation: 0,
      color: c.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: BorderSide(color: c.border),
      ),
      margin: const EdgeInsets.only(bottom: 16),
    ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.menuBg,
      contentTextStyle: TextStyle(fontSize: 13, color: c.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.menuBg,
      barrierColor: c.overlay,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.textPrimary),
      contentTextStyle: TextStyle(fontSize: 14, height: 1.6, color: c.textSecondary),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.menuBg,
      modalBarrierColor: c.overlay,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.menuBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.accent,
      unselectedLabelColor: c.textMuted,
      indicatorColor: c.accent,
      dividerColor: c.border,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    // 玻璃页全部透明，M3 缩放过渡的旧页慢淡出会与新页半透明叠加产生跳变；
    // 改为快速淡出/淡入（fade-through）：旧页先快速消失，新页再淡入
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: _FadeThroughTransitionsBuilder(),
      TargetPlatform.iOS: _FadeThroughTransitionsBuilder(),
      TargetPlatform.windows: _FadeThroughTransitionsBuilder(),
      TargetPlatform.macOS: _FadeThroughTransitionsBuilder(),
      TargetPlatform.linux: _FadeThroughTransitionsBuilder(),
    }),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.isDark ? c.bg : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: BorderSide(color: c.borderStrong),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.accent)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.inputFill,
      hintStyle: TextStyle(color: c.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.borderStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.borderStrong),
      ),
      // 聚焦光环 = 香槟金（anticlass --ring）
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.gold, width: 1.5),
      ),
    ),
  );
}

class CampusApp extends StatefulWidget {
  const CampusApp({super.key});

  @override
  State<CampusApp> createState() => _CampusAppState();
}

class _CampusAppState extends State<CampusApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 跟随系统模式下，系统深浅色切换时整体重建
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final mode = AppState.I.themeMode;
        final systemDark = WidgetsBinding
            .instance.platformDispatcher.platformBrightness == Brightness.dark;
        final dark = mode == ThemeMode.dark || (mode == ThemeMode.system && systemDark);
        final palette = dark ? GlassPalette.dark : GlassPalette.light;
        SemColors.p = palette; // 全站 SemColors 引用随主题取值
        return MaterialApp(
          title: 'AntiSIT',
          navigatorKey: navKey,
          theme: buildGlassTheme(palette),
          darkTheme: buildGlassTheme(GlassPalette.dark),
          themeMode: mode,
          // 中文：日期/时间选择器、长按菜单等 Material 组件默认是英文，必须在这里挂 delegates
          locale: appLocale,
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          // 全局液态玻璃场景底：Scaffold 全透明，光斑透出玻璃「折射」感
          builder: (context, child) => GlassBackground(child: child!),
          home: const BootPage(),
        );
      },
    );
  }
}

/// 启动流：不强制登录——加载本地设置后直接进主页。
/// 有 token 直接用（401 时请求层自动 refresh/重登）；未登录由各页面的门控引导。
class BootPage extends StatefulWidget {
  const BootPage({super.key});

  @override
  State<BootPage> createState() => _BootPageState();
}

class _BootPageState extends State<BootPage> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await AppState.I.load();
    // 调试构建：学校档案指向本机回环时，拉起本地模拟校园服务（直连模式无校园网也能测）
    await MockCampusServer.instance.ensureIfConfigured();
    // 上课提醒：打开 App 就按当前课表重排未来若干天的定时通知（不阻塞进主页）
    unawaited(_initReminders());
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
  }

  Future<void> _initReminders() async {
    try {
      await ClassReminderService.I.loadEnabled();
      await ClassReminderService.I.reschedule();
    } catch (e) {
      debugPrint('[上课提醒] 启动排期失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/sit-mark.png', width: 96, height: 96),
            const SizedBox(height: 16),
            Text('AntiSIT', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
