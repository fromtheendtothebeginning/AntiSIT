import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:campus_core/campus_core.dart';
import 'page_transitions.dart';
import 'pages/boot_page.dart';
import 'pages/home_page.dart';
import 'pages/plugin_manager_page.dart';
import 'plugins/bootstrap.dart';

/// 中文环境：日期 / 时间选择器、长按菜单等 Material 内置文案默认是英文，必须挂这些 delegates。
/// 抽成常量便于单测直接复用（测试自己搭 MaterialApp 时也要挂同一份）。
const appLocale = Locale('zh');
const appSupportedLocales = <Locale>[Locale('zh'), Locale('en')];
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// 告诉引擎返回事件交给 Flutter 处理（Android 预测式返回的前提）。
///
/// 框架自己也会做，但要求生命周期处于可交互状态，未就位时静默跳过；这里不设这个条件。
bool onNavigationNotification(NavigationNotification notification) {
  unawaited(SystemNavigator.setFrameworkHandlesBack(notification.canHandlePop));
  return true;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 敏感凭据走加密存储（Keystore）：默认内存实现不持久化，必须在这里装真机版
  SecureStore.I = FlutterSecureStore();
  // 竖屏锁定：页面布局按竖屏设计
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // 插件注册表必须在 runApp 之前装好：首帧就要按当前主题插件的色板渲染
  PluginRegistry.I = buildAppRegistry();
  // 登录页属于 core，主壳属于本包：把「回到主壳」的回调反向注入给 core
  hostShellBuilder = () => const HomePage();
  // 风险提醒拦下付款码 / 充值时，引导按钮要跳到本包的插件管理页
  hostPluginManagerBuilder = () => const PluginManagerPage();
  // 直连模式的学校系统验证码输入弹窗（服务器模式用不到）
  installDirectCaptchaPrompt();
  runApp(const CampusApp());
}

/// 由当前主题插件的色板构建全站 ThemeData。
ThemeData buildAppTheme(GlassPalette c) {
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
      centerTitle: false,
      foregroundColor: c.textPrimary,
      iconTheme: IconThemeData(color: c.textPrimary),
      // 悬浮顶栏标题：比正文重一档，压在渐变模糊上也稳
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: c.textPrimary,
      ),
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
    // 玻璃页全透明，M3 缩放过渡的旧页慢淡出会与新页半透明叠加产生跳变
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveOrFadeThroughBuilder(),
      TargetPlatform.iOS: SlidePageTransitionsBuilder(),
      TargetPlatform.windows: SlidePageTransitionsBuilder(),
      TargetPlatform.macOS: SlidePageTransitionsBuilder(),
      TargetPlatform.linux: SlidePageTransitionsBuilder(),
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

/// App 根组件：跟随主题插件与外观设置重建全站配色与场景底。
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

  /// 跟随系统模式下，系统深浅色切换时整体重建。
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // 主题插件也能换主题：色板来自注册表里当前生效的主题插件
      listenable: Listenable.merge([AppState.I, PluginRegistry.I]),
      builder: (context, _) {
        final mode = AppState.I.themeMode;
        final systemDark = WidgetsBinding
            .instance.platformDispatcher.platformBrightness == Brightness.dark;
        final dark = mode == ThemeMode.dark || (mode == ThemeMode.system && systemDark);
        final theme = PluginRegistry.I.theme;
        final brightness = dark ? Brightness.dark : Brightness.light;
        // 拖动「外观」滑块时，整站配色在浅色板与深色板之间插值（松手落到所选那档）
        final preview = AppState.I.appearancePreviewDark;
        final palette = preview == null
            ? theme.palette(brightness)
            : GlassPalette.lerp(
                theme.palette(Brightness.light), theme.palette(Brightness.dark), preview);
        SemColors.p = palette; // 全站 SemColors 引用随主题取值
        return MaterialApp(
          title: 'AntiSIT',
          navigatorKey: navKey,
          // 预览中：Material 那套（对话框 / 开关 / 水波纹）也跟着用混合色板
          theme: buildAppTheme(preview == null ? theme.palette(Brightness.light) : palette),
          darkTheme: buildAppTheme(preview == null ? theme.palette(Brightness.dark) : palette),
          themeMode: preview == null ? mode : ThemeMode.light,
          locale: appLocale,
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          onNavigationNotification: onNavigationNotification,
          // 记录顶层路由是不是页面：只有页面盖页面才搬旧页
          navigatorObservers: [TopRouteKindObserver()],
          // 全局场景底：Scaffold 全透明，光斑（由主题插件给）透出玻璃「折射」感
          builder: (context, child) => GlassBackground(
              wells: theme.wells(preview == null ? brightness : (preview >= 0.5 ? Brightness.dark : Brightness.light)),
              child: child!),
          home: const BootPage(),
        );
      },
    );
  }
}
