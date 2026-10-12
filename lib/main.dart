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

/// 返回手势所处的阶段（决定画面由谁驱动）。
enum _BackPhase {
  /// 没参与这次手势：普通导航，走淡入淡出。
  none,

  /// 手指还在屏幕上：位移 1:1 跟手。
  drag,

  /// 松手提交：从松手位置继续滑出屏幕并淡出。
  commit,

  /// 松手取消：从松手位置滑回原位。
  return_,
}

/// 预测式返回手势期间的「覆盖率」（1 = 顶层页全盖住下层页，0 = 已滑走；
/// null = 没有手势在进行）。被盖住的页据此做**渐进磨砂**：
/// 手势前 1/3 隔着重磨砂，1/3 → 2/3 之间线性变清楚（插值），之后完全清晰。
/// 拖动时它就是顶层页的动画值；提交后按实际滑出进度提前归零（见 [_commitT]）。
final ValueNotifier<double?> predictiveBackCover = ValueNotifier(null);

/// 覆盖进度 → 下层页的磨砂遮罩不透明度（0..0.45）。手势进度 g = 1 - v：
/// g ≤ 1/3 时最「糊」（下层刚要露面），1/3 → 2/3 线性减到 0，之后不再磨砂。
///
/// **为什么是遮罩不是高斯模糊**：全屏 ImageFiltered 逐帧 saveLayer，
/// 中低端机收尾掉帧、滤镜卸载时还会跳一帧（实测「最后卡顿一下、割裂」）；
/// 磨砂遮罩是纯色填充，零合成层开销，观感同为「隔着一层看不清」。
double _coverFrost(double v) =>
    0.45 * (1 - (((1 - v) - 1 / 3) / (1 / 3)).clamp(0.0, 1.0));

class _PredictiveOrFadeThroughState extends State<_PredictiveOrFadeThrough>
    with WidgetsBindingObserver {
  static const _fade = _FadeThroughTransitionsBuilder();

  /// 一律按「从左边返回」那套走：不论手指从哪条边划进来，当前页都往右滑出、
  /// 上一页从左面露出来（用户要求：不跟着手势边换方向）。
  static const double _dir = 1;

  /// 拖动期间当前页最多淡掉多少：见 [_gestureView]。1.0 = 进度 1/3 时顶层页只剩
  /// 67% 不透明度——下层页（前 1/3 已淡入到位）隔着这层半透明 + 模糊刚好「看得见」，
  /// 2/3 时只剩 33%，配合模糊已清完，与模糊插值的节奏对齐。
  static const double _dragFade = 1.0;

  /// 松手提交后，滑出 / 淡出只用框架反向窗口的前 60%（≈180ms）走完。
  /// 不能等 controller 自己降回松手值：框架在提交时先把它拉回 1.0 再线性反向，
  /// 拖得越深等得越久（实测拖到 0.8 松手要先冻 240ms 才动）——用户反馈
  /// 「松开后没有继续滑，要先停一下」。用前 60% 则一松手就走，且整体更快。
  static const double _commitSpan = 0.6;

  _BackPhase _phase = _BackPhase.none;

  /// 松手那一刻的动画值（= 1 - 手势进度）。提交 / 取消后的动画都从它续上，
  /// 保证松手前后画面的位移、缩放是连续的，不会跳。
  double _releaseV = 1;

  /// 提交后 controller 反弹到的最大值（正常就是 1.0，见 [_commitT]）。
  double _commitFrom = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 手势期间把覆盖率发布给被盖住的页（渐进磨砂 / 揭露用）。
    // 动画监听在帧调度阶段触发，不在 build 里改 ValueNotifier（会撞上 build 期重建）。
    widget.animation.addListener(_publishCover);
  }

  void _publishCover() {
    if (_phase == _BackPhase.none) return;
    final v = widget.animation.value.clamp(0.0, 1.0);
    final done = (_phase == _BackPhase.return_ && v >= 1.0) ||
        (_phase == _BackPhase.commit && v <= 0.0);
    if (done) {
      predictiveBackCover.value = null;
    } else if (_phase == _BackPhase.commit) {
      if (v > _commitFrom) _commitFrom = v;
      // 下层页的揭露按「实际滑出进度」（1 - 位移/屏宽）走：等于拖动时的 v，
      // 提交后又跟着加快后的滑出一起归零。框架把动画值拉回 1.0 的那一跳
      // 不能外漏——漏出去下层页会先瞬间消失再罩上磨砂，闪一下。
      predictiveBackCover.value = _releaseV * (1 - _commitT(v));
    } else {
      predictiveBackCover.value = v;
    }
  }

  /// 提交后滑出的进度（0 = 刚松手，1 = 滑完）：起点取 [_commitFrom]——
  /// 框架提交时把 controller 拉回 1.0，它就是 1.0；若哪天框架改成从松手值
  /// 反向，起点自然是松手值，公式同样从 0 起算。只用窗口前 [_commitSpan] 走完。
  double _commitT(double v) {
    if (_commitFrom <= 0) return 0;
    final u = ((_commitFrom - v) / _commitFrom).clamp(0.0, 1.0);
    return (u / _commitSpan).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    widget.animation.removeListener(_publishCover);
    if (_phase != _BackPhase.none) predictiveBackCover.value = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ===== WidgetsBindingObserver：接管系统返回手势，其余交给 Flutter 自己的路由实现 =====

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    // 按键返回不接管；不能返回的页（首页 / 被压住的页）也返回 false，
    // 让事件继续往后传——观察者按注册顺序通知，只有当前那一页该接。
    // 「预测式返回动画」关掉时同样不接管：框架对没人接的手势会在松手提交时
    // 按普通返回 pop（走淡入淡出），手势期间画面不动。
    if (backEvent.isButtonEvent ||
        !AppState.I.predictiveBack ||
        !widget.route.isCurrent ||
        !widget.route.popGestureEnabled) {
      return false;
    }
    widget.route.handleStartBackGesture(progress: 1 - backEvent.progress);
    if (mounted) {
      setState(() => _phase = _BackPhase.drag);
    }
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) =>
      widget.route.handleUpdateBackGestureProgress(progress: 1 - backEvent.progress);

  @override
  void handleCancelBackGesture() {
    _releaseV = widget.animation.value;
    // 松手回弹：路由自己把动画走回去
    widget.route.handleCancelBackGesture();
    if (mounted) setState(() => _phase = _BackPhase.return_);
  }

  @override
  void handleCommitBackGesture() {
    _releaseV = widget.animation.value;
    _commitFrom = 0;
    // 相位要先切：route.handleCommitBackGesture() 内部会把动画值拉回 1.0，
    // 那一跳会同步通知 [_publishCover]，相位还是 drag 的话会被当成拖动值发布。
    if (mounted) setState(() => _phase = _BackPhase.commit);
    widget.route.handleCommitBackGesture();
  }

  static double _mix(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    // 回位动画走完（动画回到 1）就交还给淡入淡出，之后这页被盖住时还能正常淡出
    if (_phase == _BackPhase.return_ && widget.animation.value >= 1.0) {
      _phase = _BackPhase.none;
    }
    if (_phase == _BackPhase.none) {
      // 被盖住的页：预测式返回手势的另一面。手势进行中（cover 非 null）
      // 下层页在**手势前 1/3** 就淡入到位并按覆盖进度模糊——
      // 原来走淡入淡出的旧曲线，要到手势走完约 2/3 才开始出现，
      // 用户实测「1/3 时完全看不到」。没有手势（null）时用普通淡入淡出。
      //
      // 「手势还在进行」也要走这条：提交后本页立刻变成 current（route 已被 pop），
      // 但手势的退场动画还在放。若此刻切回旧淡入淡出曲线，secondary 还是 1
      // （被盖住的起点）→ 该曲线直接给整页不可见，画面会闪一下（实测有）。
      if (!widget.route.isCurrent || predictiveBackCover.value != null) {
        return ValueListenableBuilder<double?>(
          valueListenable: predictiveBackCover,
          builder: (context, cover, _) {
            if (cover == null) {
              return _fade.buildTransitions(widget.route, context, widget.animation,
                  widget.secondaryAnimation, widget.child);
            }
            // 覆盖率 cover（1 = 全盖住，0 = 已滑走）。
            // 下层页透明度：cover 1 → 2/3 之间淡入（手势前 1/3），之后保持全可见，
            // 隔着顶层页的半透明 + 磨砂露出；磨砂同前：前 1/3 最重，1/3 → 2/3 变清楚。
            final visible = 1 - ((cover - 2 / 3) / (1 / 3)).clamp(0.0, 1.0);
            final frost = _coverFrost(cover);
            final content = frost > 0.01
                ? Stack(children: [
                    widget.child,
                    // 磨砂遮罩：页面底色的半透明填充，纯色无合成层开销
                    Positioned.fill(
                      child: ColoredBox(
                          color: SemColors.bg.withValues(alpha: frost)),
                    ),
                  ])
                : widget.child;
            return Opacity(opacity: visible.clamp(0.0, 1.0), child: content);
          },
        );
      }
      // 当前页（没参与手势）：沿用自家淡入淡出，玻璃观感不变
      return _fade.buildTransitions(widget.route, context, widget.animation,
          widget.secondaryAnimation, widget.child);
    }
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, _) => _gestureView(context),
    );
  }

  /// 手势期间的画面。关键是位移：系统给的 progress 就是「手指从边缘走到对边的比例」，
  /// 乘上屏宽即手指走过的距离，所以进度 × 屏宽 = 1:1 跟手（这也是之前不跟手的原因：
  /// 只乘了 0.18）。缩放 / 圆角仍按手势进度走，提交与取消都从松手瞬间续上、不跳变。
  Widget _gestureView(BuildContext context) {
    final v = widget.animation.value.clamp(0.0, 1.0); // 1 = 完整在前，0 = 已退出
    final width = MediaQuery.sizeOf(context).width;
    const dir = _dir;

    // 松手瞬间的状态（取消 / 提交后的动画都从这里插值，避免跳变）
    final released = 1 - _releaseV;
    final releaseShift = dir * released * width;
    final releaseScale = 1 - 0.05 * released;
    final releaseRadius = 16 * released;

    final double shift;
    final double opacity;
    final double scale;
    final double radius;
    switch (_phase) {
      case _BackPhase.drag:
        final gone = 1 - v;
        shift = dir * gone * width; // 1:1 跟手
        // 不整页淡掉：拖动时要像「被手指推走」。玻璃页半透明，稍带一点淡出，
        // 两页叠在一起时不至于互相透得太花；淡得多一点是为了让「回撤到的那一页」
        // 早点露出来（原来 0.45 基本看不见后面那页）。
        opacity = 1 - _dragFade * gone;
        scale = 1 - 0.05 * gone;
        radius = 16 * gone;
      case _BackPhase.commit:
        // 松手后继续往右滑出去：一松手就走（[_commitT] 从 0 起算），
        // 并在框架窗口的前 [_commitSpan] 内滑完，比原来的 300ms 窗口快。
        final t = _commitT(v);
        shift = _mix(releaseShift, dir * width, t);
        // 从松手那一刻的实际透明度（= _releaseV）继续淡出，不能从 1 拉回：
        // 拖得深时松手页面已接近全透明，跳回 1 用户会看到「不透明度突然上升」。
        // 仍按 t≈0.7 提前淡完：滑完前上一页已经完整在场。
        opacity = (_releaseV * (1 - t * 1.45)).clamp(0.0, 1.0);
        scale = _mix(releaseScale, 0.96, t);
        radius = _mix(releaseRadius, 12, t);
      case _BackPhase.return_:
        final span = 1 - _releaseV;
        final t = span <= 0 ? 1.0 : ((v - _releaseV) / span).clamp(0.0, 1.0);
        shift = _mix(releaseShift, 0, t);
        opacity = _mix(1 - _dragFade * released, 1, t);
        scale = _mix(releaseScale, 1, t);
        radius = _mix(releaseRadius, 0, t);
      case _BackPhase.none:
        shift = 0;
        opacity = 1;
        scale = 1;
        radius = 0;
    }

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(shift, 0),
        child: Transform.scale(
          scale: scale,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: widget.child,
          ),
        ),
      ),
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
