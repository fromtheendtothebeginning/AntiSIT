import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:campus_core/campus_core.dart';
import 'pages/home_page.dart';
import 'plugins/bootstrap.dart';

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

/// 安卓的返回动画：**普通前进/返回**仍用上面的 fade-through（保持玻璃观感），
/// 但**系统返回手势**（Android 14+ 可预测式返回）交给官方 [PredictiveBackPageTransitionsBuilder]：
/// 拖动时当前页跟着手指缩小、露出上一页，松手前还能反悔取消。
///
/// 为什么不直接用官方 builder 兜底：它在「非手势导航」时会回落到
/// FadeForwardsPageTransitionsBuilder（横向滑动），那是另一套观感，
/// 会把我们特意做的淡入淡出换掉。
class _PredictiveOrFadeThroughBuilder extends PageTransitionsBuilder {
  const _PredictiveOrFadeThroughBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    return _PredictiveOrFadeThrough(
      route: route,
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

class _PredictiveOrFadeThrough extends StatefulWidget {
  const _PredictiveOrFadeThrough({
    required this.route,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final PageRoute<dynamic> route;
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  State<_PredictiveOrFadeThrough> createState() => _PredictiveOrFadeThroughState();
}

class _PredictiveOrFadeThroughState extends State<_PredictiveOrFadeThrough>
    with WidgetsBindingObserver {
  static const _fade = _FadeThroughTransitionsBuilder();

  /// 正跟着手指做预测式返回（松手前一直为 true）。
  bool _dragging = false;

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

  // ===== WidgetsBindingObserver：接管系统返回手势，其余交给 Flutter 自己的路由实现 =====

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    // 按键返回不接管；不能返回的页（首页 / 被压住的页）也返回 false，
    // 让事件继续往后传——观察者按注册顺序通知，只有当前那一页该接。
    if (backEvent.isButtonEvent || !widget.route.isCurrent || !widget.route.popGestureEnabled) {
      return false;
    }
    widget.route.handleStartBackGesture(progress: 1 - backEvent.progress);
    if (mounted) setState(() => _dragging = true);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) =>
      widget.route.handleUpdateBackGestureProgress(progress: 1 - backEvent.progress);

  @override
  void handleCancelBackGesture() {
    // 松手回弹：路由自己把动画走回去
    widget.route.handleCancelBackGesture();
    if (mounted) setState(() => _dragging = false);
  }

  @override
  void handleCommitBackGesture() => widget.route.handleCommitBackGesture();

  @override
  Widget build(BuildContext context) {
    if (!_dragging) {
      // 普通前进 / 点返回：沿用自家淡入淡出，玻璃观感不变
      return _fade.buildTransitions(widget.route, context, widget.animation,
          widget.secondaryAnimation, widget.child);
    }
    // 手势进行中：当前页跟着手指缩小 + 收圆角 + 淡出，露出下面那一页。
    // 玻璃页是半透明的，所以淡出比原样缩更要紧（否则两页内容会叠影）。
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, _) {
        final v = widget.animation.value.clamp(0.0, 1.0); // 1 = 完整在前，0 = 已退出
        final gone = 1 - v;
        final width = MediaQuery.sizeOf(context).width;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            // 跟手右移一点：像原生那样把当前页「推走」，露出下面那一页
            offset: Offset(gone * width * 0.18, 0),
            child: Transform.scale(
              scale: 0.90 + 0.10 * v,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24 * gone),
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 告诉引擎：返回事件交给 Flutter 处理（Android 预测式返回的前提）。
///
/// 引擎只有收到这句话才会注册带进度的返回回调，我们才能收到
/// `WidgetsBindingObserver.handleStartBackGesture`；否则系统按自己的默认行为处理
/// ——把 Activity 弹掉 / 回桌面，预测式动画和「跟手取消」都无从谈起。
///
/// 框架默认也会做这件事（`WidgetsApp` 内部监听 NavigationNotification），
/// 但它要求 App 生命周期必须是 resumed / inactive / paused / hidden 之一，
/// 状态还没到位时**静默跳过**。这里不设这个条件：只要还有可返回的路由就说。
bool onNavigationNotification(NavigationNotification notification) {
  unawaited(SystemNavigator.setFrameworkHandlesBack(notification.canHandlePop));
  return true;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 竖屏锁定：手机横过来也不跟着陀螺仪转（页面布局按竖屏设计）
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // 组装插件注册表：核心插件 + 各插件包（清单由 tool/gen_plugins.dart 生成）。
  // 必须在 runApp 之前装好：首帧就要按当前主题插件的色板渲染。
  PluginRegistry.I = buildAppRegistry();
  // 登录页属于 core，主壳属于本包：把「回到主壳」的回调反向注入给 core
  hostShellBuilder = () => const HomePage();
  // 直连模式的学校系统验证码输入弹窗（服务器模式用不到）
  installDirectCaptchaPrompt();
  runApp(const CampusApp());
}

/// 由色板构建全站 ThemeData。色板来自当前主题插件（packages/plugin_theme_*），
/// 所以换主题只换色板，这里的组件主题不跟着动。
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
      // 安卓：系统返回手势走官方预测式动画，其余仍是淡入淡出
      TargetPlatform.android: _PredictiveOrFadeThroughBuilder(),
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
      // 主题插件也能换主题：色板来自注册表里当前生效的主题插件
      listenable: Listenable.merge([AppState.I, PluginRegistry.I]),
      builder: (context, _) {
        final mode = AppState.I.themeMode;
        final systemDark = WidgetsBinding
            .instance.platformDispatcher.platformBrightness == Brightness.dark;
        final dark = mode == ThemeMode.dark || (mode == ThemeMode.system && systemDark);
        final theme = PluginRegistry.I.theme;
        final brightness = dark ? Brightness.dark : Brightness.light;
        final palette = theme.palette(brightness);
        SemColors.p = palette; // 全站 SemColors 引用随主题取值
        return MaterialApp(
          title: 'AntiSIT',
          navigatorKey: navKey,
          theme: buildAppTheme(theme.palette(Brightness.light)),
          darkTheme: buildAppTheme(theme.palette(Brightness.dark)),
          themeMode: mode,
          // 中文：日期/时间选择器、长按菜单等 Material 组件默认是英文，必须在这里挂 delegates
          locale: appLocale,
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          onNavigationNotification: onNavigationNotification,
          // 全局场景底：Scaffold 全透明，光斑（由主题插件给）透出玻璃「折射」感
          builder: (context, child) =>
              GlassBackground(wells: theme.wells(brightness), child: child!),
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
    // 插件清单：读启停状态与当前主题（此后底栏、工具宫格、设置项都按启用集合组装）
    await PluginRegistry.I.load();
    // 各启用插件的初始化：AI 配置、上课提醒排期、调试用的本地模拟校园服务
    await PluginRegistry.I.initAll();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
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
