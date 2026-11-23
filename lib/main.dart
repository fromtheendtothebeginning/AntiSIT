import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:campus_core/campus_core.dart';
import 'pages/home_page.dart';
import 'update_download.dart';
import 'pages/plugin_manager_page.dart';
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

/// 当前最顶层路由是不是「页面」（[PageRoute]）。
///
/// 只有页面盖页面时才做「旧页左移 + 变暗」；弹窗 / 菜单 / 底部菜单也会驱动被盖页的
/// secondaryAnimation，如果不过滤，点开右上角菜单整个页面就会往左跑、变暗。
final ValueNotifier<bool> topRouteIsPage = ValueNotifier<bool>(true);

/// 跟踪顶层路由类型（注册到 MaterialApp.navigatorObservers）。
class TopRouteKindObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      topRouteIsPage.value = route is PageRoute;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      topRouteIsPage.value = previousRoute is PageRoute;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      topRouteIsPage.value = newRoute is PageRoute;
}
/// 页面转场（默认前进 / 返回）：**整页整体位移 + 上层页不透明覆盖 + 旧页轻微渐暗**。
///
/// 前进（push）：
/// * 新页整块从屏幕右侧滑入到 0（先快后慢、末尾缓慢停住），并**完整盖住**旧页；
/// * 旧页整体向左平移 20% 屏宽，同时叠一层很浅的暗色。
///
/// 返回（pop）：上面这套的反向——
/// * 当前页整块向右滑出屏幕；
/// * 下层页从左移 20% 的位置滑回 0，同时把压暗褪掉。
///
/// 不做淡入淡出、不做圆角、不做缩放。
///
/// 三个关键实现细节：
/// 1. **上层页要垫一张和全局场景底一模一样的底**：本 App 页面是半透明的（玻璃卡片、
///    内容渐隐），不垫的话滑入时会把下层页透出来，看起来像「两个页面同时显示」。
///    垫底常驻组件树、只改 Opacity（纯绘制），不做结构变化。
/// 2. **不能用 SlideTransition / FractionalTranslation**：它的 applyPaintTransform
///    要读 child.size，弹窗 localToGlobal 时页面正在布局会抛断言（课程表「更多」）。
/// 3. **弹窗 / 菜单不算「新页」**：只有 PageRoute 盖上来才搬页面（[topRouteIsPage]），
///    否则点开菜单整页会跟着左移变暗。
class _SlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _SlidePageTransitionsBuilder();

  /// 旧页被推走的距离（屏宽比例）。
  static const double oldShift = 0.20;

  /// 旧页最深压暗（只用来拉开层次）。
  static const double oldDim = 0.10;

  /// 前进：时长更长；曲线更陡（起步就走、尾巴收得慢）。
  static const Duration pushDuration = Duration(milliseconds: 520);

  /// 返回：时长更短；曲线更缓（起步柔和，不会「一闪而过」）。
  static const Duration popDuration = Duration(milliseconds: 320);

  @override
  Duration get transitionDuration => pushDuration;

  @override
  Duration get reverseTransitionDuration => popDuration;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    // 首屏也包一层：它自己进场时动画值已是 1（不位移），但被上层页覆盖时要跟着
    // 左移变暗，否则前进观感左右不对称。
    return _SlidePageTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// 前进用的缓动：起步就动、末尾缓慢收住（相对「陡」）。
/// 注意别用极端 expo-out（如 Cubic(0.16, 1, 0.3, 1)）：25% 时长就走完一半以上，
/// 观感是「旧页闪一下就被盖住，后面几乎不动」。
const Curve _pushCurve = Cubic(0.20, 0.85, 0.20, 1.0);

/// 返回用的缓动：起步更柔和、整体更「缓」，配合更短的时长。
const Curve _popCurve = Cubic(0.30, 0.55, 0.35, 1.0);

/// 被盖住的旧页：延后 22% 才开始退让，避免「闪一下就被推开」。
const Curve _coveredCurve = Interval(0.22, 1.0, curve: _pushCurve);

/// 按动画方向取曲线：正向（前进）用陡的，反向（返回）用缓的。
Curve _curveFor(Animation<double> a) =>
    a.status == AnimationStatus.reverse ? _popCurve : _pushCurve;

class _SlidePageTransition extends StatelessWidget {
  const _SlidePageTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [animation, secondaryAnimation, topRouteIsPage]),
      child: child,
      builder: (context, child) {
        final width = MediaQuery.sizeOf(context).width;
        final covered = topRouteIsPage.value && secondaryAnimation.value > 0.001;

        double shift;
        double dim;
        if (covered) {
          // 镜头在这里不动，只是被上层页推走：左移 20% + 渐暗。
          // 前进时 0 → -20%，返回时 -20% → 0（同一公式，动画值反向即可）。
          //
          // 关键：**延后这个动作**（前 22% 时长里旧页原地不动）。不延后的话新页
          // 一起步就把旧页推开、压低，观感是「旧页闪一下就被盖住」；延后之后旧页
          // 一直是完整、亮的状态，直到被新页盖住一部分才开始退让。
          final s = _coveredCurve.transform(secondaryAnimation.value);
          shift = -_SlidePageTransitionsBuilder.oldShift * width * s;
          dim = _SlidePageTransitionsBuilder.oldDim * s;
        } else {
          // 自己进出：前进从右侧滑到 0；返回从 0 滑出到右侧（同一公式）。
          final c = _curveFor(animation).transform(animation.value);
          shift = (1 - c) * width;
          dim = 0;
        }

        // 转场期间让页面不透明（垫一张与全局场景底一致的底），静止时再透明。
        //
        // 判断必须看**动画状态**而不是数值：用数值判断会漏掉转场的第一帧——
        // 返回刚开始时 nimation.value 还是 1（还没开始降），于是这一帧不垫底，
        // 上层页是半透明的、下层页从玻璃里透出来；下一帧数值一降立刻垫上，下层页又被
        // 盖住 —— 观感就是「返回动画刚开始闪一下」。状态（forward / reverse）在第一帧
        // 就已经切换，所以按状态判断不会有这个空窗。
        final busy = animation.status == AnimationStatus.forward ||
            animation.status == AnimationStatus.reverse ||
            (topRouteIsPage.value &&
                (secondaryAnimation.status == AnimationStatus.forward ||
                    secondaryAnimation.status == AnimationStatus.reverse));

        return Transform.translate(
          offset: Offset(shift, 0),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              // 场景底（常驻、只改显隐与压暗透明度，不触发布局）
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: busy ? 1 : 0,
                    child: GlassScenePaint(wells: GlassScene.wells),
                  ),
                ),
              ),
              child!,
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000).withValues(alpha: dim),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}/// 安卓的返回动画：**普通前进/返回**仍用上面的 fade-through（保持玻璃观感），
/// 但**系统返回手势**（Android 14+ 可预测式返回）交给官方 [PredictiveBackPageTransitionsBuilder]：
/// 拖动时当前页跟着手指缩小、露出上一页，松手前还能反悔取消。
///
/// 为什么不直接用官方 builder 兜底：它在「非手势导航」时会回落到
/// FadeForwardsPageTransitionsBuilder（横向滑动），那是另一套观感，
/// 会把我们特意做的淡入淡出换掉。
class _PredictiveOrFadeThroughBuilder extends PageTransitionsBuilder {
  const _PredictiveOrFadeThroughBuilder();

  // 路由的过渡时长取的是「当前平台这个 builder」的值（MaterialRouteTransitionMixin
  // 里读 _getPageTransitionBuilder(context)?.transitionDuration），安卓这条链走的是
  // 本类，所以时长要在这里同步，否则 _SlidePageTransitionsBuilder 上改的时长对
  // 安卓不生效（真机/模拟器上仍是 300ms）。
  @override
  Duration get transitionDuration => _SlidePageTransitionsBuilder.pushDuration;

  @override
  Duration get reverseTransitionDuration => _SlidePageTransitionsBuilder.popDuration;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    return _PredictiveOrFadeThrough(
      route: route,
      // 画面沿用默认转场（同一个 builder），手势只驱动它的动画值
      child: _SlidePageTransitionsBuilder().buildTransitions(
          route, context, animation, secondaryAnimation, child),
    );
  }
}

/// 预测式返回（Android 14+ 从屏幕边缘拖入）：**画面直接用默认返回动画**，
/// 由手指驱动路由的动画值。
///
/// 早先这里自己算了一套手势画面（1:1 位移 + 缩放 + 整页淡出 + 圆角裁剪 + 下层磨砂），
/// 和默认返回完全是两套观感，且每帧要开好几层全屏合成。现在只做一件事：
/// 把系统手势转给路由（handleStartBackGesture / handleUpdateBackGestureProgress），
/// 让 [PageTransitionsBuilder] 用和「按返回键」完全相同的动画去渲染——
/// 手指拖多少，页面就按同一套曲线走到哪；松手提交/取消交给框架收尾。
///
/// 于是预测式返回与默认返回**天然一致**：旧页左移 20% + 轻微渐暗、上层页从右侧让出。
class _PredictiveOrFadeThrough extends StatefulWidget {
  const _PredictiveOrFadeThrough({
    required this.route,
    required this.child,
  });

  final PageRoute<dynamic> route;
  final Widget child;

  @override
  State<_PredictiveOrFadeThrough> createState() => _PredictiveOrFadeThroughState();
}

class _PredictiveOrFadeThroughState extends State<_PredictiveOrFadeThrough>
    with WidgetsBindingObserver {
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

  // ===== WidgetsBindingObserver：接管系统返回手势，画面交给默认转场 =====

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    // 按键返回不接管；不能返回的页（首页 / 被压住的页）也返回 false，
    // 让事件继续往后传——观察者按注册顺序通知，只有当前那一页该接。
    // 「预测式返回动画」关掉时同样不接管：系统会按普通返回处理（走默认动画）。
    if (backEvent.isButtonEvent ||
        !AppState.I.predictiveBack ||
        !widget.route.isCurrent ||
        !widget.route.popGestureEnabled) {
      return false;
    }
    widget.route.handleStartBackGesture(progress: 1 - backEvent.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) =>
      widget.route.handleUpdateBackGestureProgress(progress: 1 - backEvent.progress);

  @override
  void handleCancelBackGesture() => widget.route.handleCancelBackGesture();

  @override
  void handleCommitBackGesture() => widget.route.handleCommitBackGesture();

  /// 画面完全由外面的默认转场负责，这里只透传。
  @override
  Widget build(BuildContext context) => widget.child;
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
  // 敏感凭据改走加密存储（Keystore）：默认的内存实现不持久化，必须在这里装上真机版
  SecureStore.I = FlutterSecureStore();
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
  // 「插件管理」页也在本包：风险提醒拦下付款码 / 充值时，引导按钮要跳到它
  hostPluginManagerBuilder = () => const PluginManagerPage();
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
      centerTitle: false,
      foregroundColor: c.textPrimary,
      iconTheme: IconThemeData(color: c.textPrimary),
      // 悬浮顶栏的标题：比正文略重一档，压在渐变模糊上也稳
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
    // 玻璃页全部透明，M3 缩放过渡的旧页慢淡出会与新页半透明叠加产生跳变；
    // 改为快速淡出/淡入（fade-through）：旧页先快速消失，新页再淡入
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      // 安卓：系统返回手势走官方预测式动画，其余仍是淡入淡出
      TargetPlatform.android: _PredictiveOrFadeThroughBuilder(),
      TargetPlatform.iOS: _SlidePageTransitionsBuilder(),
      TargetPlatform.windows: _SlidePageTransitionsBuilder(),
      TargetPlatform.macOS: _SlidePageTransitionsBuilder(),
      TargetPlatform.linux: _SlidePageTransitionsBuilder(),
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
        // 拖动「外观」滑块时整站配色在浅色板与深色板之间插值（松手落到所选那档）
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
          // 中文：日期/时间选择器、长按菜单等 Material 组件默认是英文，必须在这里挂 delegates
          locale: appLocale,
          supportedLocales: appSupportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          onNavigationNotification: onNavigationNotification,
          // 记录顶层路由是不是页面：只有页面盖页面才做「旧页左移 + 变暗」
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
    // 课表也要在插件初始化前读出来：流体云 / 上课提醒 / 桌面卡片都靠它在启动时排期，
    // 否则插件先跑会拿空课表把上一次排好的闹钟清掉。
    await TimetableStore.instance.load();
    // 各启用插件的初始化：AI 配置、上课提醒排期、调试用的本地模拟校园服务
    await PluginRegistry.I.initAll();
    // 上次更新下载的安装包装完就没用了（80MB 一份，每升一版留一个）：
    // 启动时顺手清掉，别让缓存目录一直涨。放最后、且不等它——清扫不该拖慢首屏。
    unawaited(UpdateDownloader.I.sweepCache());
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
