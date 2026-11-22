import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_state.dart';
import 'theme_palette.dart';

/// 顶栏里「渐变段」占顶栏高度的比例：模糊只发生在顶栏自己的范围内，
/// 上 60% 保持最强模糊，靠底部 40% 从最强线性降到 0——内容从顶栏底边露出时是清晰的。
const double kGlassBarFadeFraction = 0.4;

/// 背景（顶栏那条渐变模糊带）的最大模糊强度（逻辑像素）。**比按钮小一档**：
/// 按钮是「隔着玻璃看内容」的强模糊，背景只把穿过去的内容压淡。
const double kGlassBarBlurSigma = 8;

/// 模糊值随纵坐标的衰减曲线：顶栏顶部一段保持最强，最后 [kGlassBarFadeFraction]
/// 那一段按 (1 - f)^curve 收敛到 0（数值越大越「顶强底缓」）。
const double kGlassBarBlurCurve = 1.8;

/// 顶栏是否用悬浮玻璃样式（「我的 → 外观」里的开关，默认开）。
///
/// 页面用它决定 `Scaffold.extendBodyBehindAppBar`；[glassAppBar] 内部也看它：
/// 关掉时退回普通 [AppBar]（内容不再从顶栏底下穿过），[glassTopInset] 返回 0。
bool get glassTopBarEnabled => AppState.I.glassTopBar;

/// 页面第一个滚动区 / 内容的顶部内边距：躲开悬浮顶栏（状态栏 + 标题栏）。
/// 开关关闭时返回 0（普通 AppBar 本身占位，内容不需要额外留白）。
///
/// **必须在页面 `build` 的 context（Scaffold 之上）取**：开了
/// `Scaffold.extendBodyBehindAppBar` 之后，body 里的 `MediaQuery` 已经被
/// `removePadding` 处理过——`padding.top` 清零、`viewPadding.top` 也被减到 0，
/// 在 body 内部调用会算出「只有标题栏、没有状态栏」的偏小值（内容会顶进顶栏里）。
double glassTopInset(
  BuildContext context, {
  double toolbarHeight = kToolbarHeight,
}) {
  if (!glassTopBarEnabled) return 0;
  final mq = MediaQuery.maybeOf(context);
  return (mq?.viewPadding.top ?? 0) + toolbarHeight;
}

/// 玻璃悬浮顶栏：标题与按钮浮在「越往上越糊」的高斯模糊之上，内容从它底下穿过去。
///
/// 返回的仍是真 [AppBar]（不是自绘工具栏）：返回键、tooltip、状态栏图标深浅、
/// 标题居中/省略等系统行为全部保持原样，只是背景换成了渐变模糊。
/// 页面侧还要把 `Scaffold.extendBodyBehindAppBar` 打开、并给第一个滚动区加上
/// [glassTopInset] 的顶部留白，内容才会从顶栏底下穿过去而不是被压在下面。
///
/// 需要 `context` 是为了自己决定返回键：只有能 pop 的页面才给 [BackButton]，
/// 但返回键和右上角图标都要套上悬浮玻璃圆钮（框架自动加的返回键套不了样式）。
AppBar glassAppBar(
  BuildContext context, {
  required Widget title,
  List<Widget>? actions,
  Widget? leading,
  bool centerTitle = true,
  bool automaticallyImplyLeading = true,
  double toolbarHeight = kToolbarHeight,
  PreferredSizeWidget? bottom,
  double titleSpacing = NavigationToolbar.kMiddleSpacing,
}) {
  // 开关关闭：退回普通 AppBar（主题本身就是透明底，所以和加这个功能之前一致）
  if (!glassTopBarEnabled) {
    return AppBar(
      centerTitle: centerTitle,
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading,
      actions: actions,
      toolbarHeight: toolbarHeight,
      titleSpacing: titleSpacing,
      title: title,
      bottom: bottom,
    );
  }
  final bottomHeight = bottom?.preferredSize.height ?? 0;
  final autoLeading =
      automaticallyImplyLeading &&
          leading == null &&
          (ModalRoute.of(context)?.canPop ?? false)
      ? const BackButton()
      : null;
  final leadingWidget = leading ?? autoLeading;
  return AppBar(
    backgroundColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: centerTitle,
    automaticallyImplyLeading: false, // 返回键由这里自己给，才能套上圆钮样式
    leading: leadingWidget == null ? null : _orb(leadingWidget, edge: 8),
    actions: actions
        ?.map((a) => a is IconButton ? _orb(a, edge: 3) : a)
        .toList(growable: false),
    toolbarHeight: toolbarHeight,
    titleSpacing: titleSpacing,
    title: title,
    // flexibleSpace 铺满整个顶栏（含状态栏）：渐变模糊只发生在顶栏自己的范围里，
    // 不向下延伸——内容从顶栏底边露出时已经是清晰的
    flexibleSpace: const IgnorePointer(child: GlassBarScrim()),
    bottom: bottom == null
        ? null
        : PreferredSize(
            preferredSize: Size.fromHeight(bottomHeight),
            child: bottom,
          ),
  );
}

/// 把标题栏里的一个按钮套成悬浮玻璃圆钮（40 直径、更实一档的玻璃面 + 强描边）。
/// [glassAppBar] 会自动处理 `IconButton` 类型的 action；包在 ListenableBuilder /
/// PopupMenuButton 之类结构里的按钮不会被识别，页面要显式用这个包一下。
Widget glassTopBarAction(Widget child, {double edge = 3}) => _orb(child, edge: edge);

/// 悬浮圆钮：把标题栏里的按钮套成 40 直径的玻璃圆片。
/// 圆片内不再做第二层模糊（会和顶栏的模糊层嵌套、在 Impeller 下产生椭圆光晕），
/// 改用比顶栏更实一档的玻璃面 + 强描边，读起来仍是「浮在模糊上的一块厚玻璃」。
Widget _orb(Widget child, {required double edge}) => Padding(
  padding: EdgeInsets.only(left: edge, right: edge),
  child: Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: SemColors.thumb,
      shape: BoxShape.circle,
      border: Border.all(color: SemColors.borderStrong),
    ),
    child: Center(
      child: IconButtonTheme(
        data: IconButtonThemeData(style: _orbStyle()),
        child: child,
      ),
    ),
  ),
);

/// 圆钮里的图标按钮样式：只留点击/图标色，背景交给外面那层玻璃（含模糊与描边）。
ButtonStyle _orbStyle() => ButtonStyle(
  fixedSize: const WidgetStatePropertyAll(Size(40, 40)),
  minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  elevation: const WidgetStatePropertyAll(0),
  foregroundColor: WidgetStatePropertyAll(SemColors.textPrimary),
  backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
  shape: const WidgetStatePropertyAll(CircleBorder()),
);

/// 顶栏「滚动中」状态：滚动期间顶栏改用**快照模糊**（见 [GlassTopBarSnapshot]），
/// 停手 150ms 后回到实时 backdrop 的磨砂。
///
/// 为什么要这样：实时 backdrop 在两个过滤趟/滚动中途会采到上一帧或中间态的内容，
/// 出现重影和噪点；而快照是「某一帧的画面 + 静态模糊」，不存在跨帧采样问题。
class GlassTopBarMotion {
  GlassTopBarMotion._();

  static final GlassTopBarMotion I = GlassTopBarMotion._();

  /// true = 正在滚动（顶栏用快照模糊）。
  final ValueNotifier<bool> scrolling = ValueNotifier<bool>(false);

  Timer? _timer;

  /// 每次滚动位移调用一次。
  void onScroll(double pixels) {
    if (!scrolling.value) scrolling.value = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 150), () {
      scrolling.value = false;
    });
  }
}

/// 顶栏快照：滚动开始时对整屏做一次截帧（约 120ms 刷新一次），
/// 截出顶栏那一条做静态模糊。相当于系统应用的「RenderEffect + 截图」做法。
class GlassTopBarSnapshot {
  GlassTopBarSnapshot._();

  static final GlassTopBarSnapshot I = GlassTopBarSnapshot._();

  /// 截帧用的根 RepaintBoundary（main.dart 里包在 MaterialApp 外层）。
  static final GlobalKey rootKey = GlobalKey(debugLabel: 'glassSnapshotRoot');

  /// 最近一帧顶栏区域的画面（逻辑像素）。
  final ValueNotifier<ui.Image?> image = ValueNotifier<ui.Image?>(null);

  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;

  /// 请求一帧快照（内部节流，避免滚动时频繁 toImage 造成卡顿）。
  void request({required double barHeight, double pixelRatio = 0.5}) {
    if (_busy) return;
    final now = DateTime.now();
    if (now.difference(_last) < const Duration(milliseconds: 120)) return;
    _last = now;
    _busy = true;
    // 滚动通知通常发生在布局/绘制阶段，直接 toImage 会拿到 debugNeedsPaint；
    // 挪到下一帧的帧后回调里再截。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _capture(barHeight: barHeight, pixelRatio: pixelRatio).whenComplete(() {
        _busy = false;
      });
    });
  }

  Future<void> _capture({
    required double barHeight,
    required double pixelRatio,
  }) async {
    try {
      final object = rootKey.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) return;
      final full = await object.toImage(pixelRatio: pixelRatio);
      final barH = (barHeight * pixelRatio).round().clamp(1, full.height);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        full,
        ui.Rect.fromLTWH(0, 0, full.width.toDouble(), barH.toDouble()),
        ui.Rect.fromLTWH(0, 0, full.width.toDouble(), barH.toDouble()),
        ui.Paint(),
      );
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(full.width, barH);
      full.dispose();
      picture.dispose();
      final old = image.value;
      image.value = cropped;
      // 旧图可能还在本帧的 RawImage 里用着，延迟释放
      if (old != null) {
        Future<void>.delayed(const Duration(milliseconds: 300), old.dispose);
      }
    } catch (_) {
      // 截帧失败就退回实时模糊，不弹错
    }
  }
}
/// 顶栏背景：一段「上强下无」的高斯模糊 + 压在上面的底色渐变。
///
/// 真机性能关键，跟社区（liquid_glass_widgets / inspire_blur）和系统实现一致：
/// * **只有一个 BackdropFilter**：backdrop 只捕获一次；
/// * 模糊用本仓库自带的 shader **单趟 2D 采样**（一次绘制）。不再叠多层模糊——
///   多层在 Impeller 下滚动时每层各自采样不同帧的 backdrop，会出重影/噪点，
///   还会把 GPU 打满；本版本 Flutter 的 ImageFilter.compose 组合两个 shader
///   filter 会静默失效，所以也不用「两趟可分离」那条路；
/// * 模糊强度随纵坐标渐变（shader 里按顶栏区域归一化），顶边最强、底边收敛到 0，
///   所以内容从顶栏底边露出来时是清晰的，没有硬边；
/// * 路由过渡期间不画模糊：过渡帧没有稳定的 backdrop，会得到一块发黑的毛玻璃；
/// * 后端不支持 shader filter（Skia / Web）时退化为**单层均匀模糊**，不再有叠层问题。
class GlassBarScrim extends StatelessWidget {
  const GlassBarScrim({
    super.key,
    this.fadeFraction = kGlassBarFadeFraction,
    this.sigma = kGlassBarBlurSigma,
    this.curve = kGlassBarBlurCurve,
  });

  final double fadeFraction;
  final double sigma;
  final double curve;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final anim = route?.animation;
    final secondary = route?.secondaryAnimation;
    final scrolling = GlassTopBarMotion.I.scrolling;
    final snapshot = GlassTopBarSnapshot.I.image;
    final animations = <Listenable>[
      if (anim != null) anim,
      if (secondary != null) secondary,
      scrolling,
      snapshot,
    ];
    return AnimatedBuilder(
      animation: Listenable.merge(animations),
      builder: (context, _) {
        final routeOk = _blurAllowed(anim, secondary);
        return _build(
          context,
          blur: routeOk && !scrolling.value,
          // 路由过渡帧没有模糊托底，色带压重一点保证标题可读
          boost: routeOk ? 1.0 : 1.35,
        );
      },
    );
  }

  /// 路由动画没跑完（进场 / 退场 / 被新页面压住的过渡帧）就不做模糊。
  static bool _blurAllowed(
    Animation<double>? primary,
    Animation<double>? secondary,
  ) {
    final primaryDone = primary == null ||
        primary.status == AnimationStatus.completed ||
        primary.status == AnimationStatus.dismissed;
    final secondaryIdle = secondary == null ||
        secondary.status == AnimationStatus.dismissed ||
        secondary.status == AnimationStatus.completed;
    return primaryDone && secondaryIdle;
  }

  Widget _build(
    BuildContext context, {
    required bool blur,
    required double boost,
  }) {
    return LayoutBuilder(
      builder: (context, cons) {
        final h = cons.maxHeight;
        final w = cons.maxWidth;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final fadeStart = (1 - fadeFraction).clamp(0.0, 1.0);
        // 滚动中：用快照 + 静态模糊（没有跨帧 backdrop 采样，不会重影/噪点）；
        // 静止：回到实时 backdrop 磨砂。
        Widget? blurLayer;
        if (blur) {
          blurLayer = _blurLayer(Size(w, h), dpr, fadeStart);
        } else if (GlassTopBarMotion.I.scrolling.value) {
          blurLayer = _snapshotLayer(w, h);
          GlassTopBarSnapshot.I.request(barHeight: h);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            if (blurLayer != null) blurLayer,
            // 底色渐变：被糊掉的内容只是色块，这层让标题和按钮在任何内容上都读得清。
            // 末段必须是「同色透明」而不是透明黑，否则线性插值会在中间混出一条暗带。
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: _tint(fadeStart, boost: boost),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 滚动中的快照模糊层：取最近一帧顶栏区域的截图，做静态高斯模糊再贴回来。
  /// 截图按 0.5 像素比存的，放大回逻辑尺寸时模糊会被放大一倍，所以 sigma 也乘 0.5。
  Widget? _snapshotLayer(double w, double h) {
    final img = GlassTopBarSnapshot.I.image.value;
    if (img == null) return null;
    return Positioned.fill(
      child: ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: sigma * 0.5,
            sigmaY: sigma * 0.5,
          ),
          child: RawImage(image: img, fit: BoxFit.fill, filterQuality: FilterQuality.low),
        ),
      ),
    );
  }
  /// 模糊层：横向一趟 + 纵向一趟两个 BackdropFilter 叠起来（后者能采到前者的输出，
  /// 等价于一次 2D 可分离高斯）。shader 不可用时退化为一层均匀模糊。
  Widget _blurLayer(Size size, double dpr, double fadeStart) {
    final hPass = _passFilter(
      size: size,
      dpr: dpr,
      fadeStart: fadeStart,
      axis: 0,
    );
    final vPass = _passFilter(
      size: size,
      dpr: dpr,
      fadeStart: fadeStart,
      axis: 1,
    );
    if (hPass == null || vPass == null) {
      return Positioned.fill(
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: const SizedBox.expand(),
          ),
        ),
      );
    }
    return Positioned.fill(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(filter: hPass, child: const SizedBox.expand()),
            BackdropFilter(filter: vPass, child: const SizedBox.expand()),
          ],
        ),
      ),
    );
  }

  /// 单趟一维高斯的滤镜；shader 不可用时返回 null。
  ui.ImageFilter? _passFilter({
    required Size size,
    required double dpr,
    required double fadeStart,
    required double axis,
  }) {
    final program = _program;
    if (program == null || !ui.ImageFilter.isShaderFilterSupported) return null;
    final shader = program.fragmentShader();
    // float uniform 下标：u_size 占 0、1（引擎写），之后依次是下面这些字段；
    // sampler 不占 float 下标（引擎绑定 backdrop）。
    shader.setFloat(2, 0); // u_region_origin.x：顶栏在屏幕左上角
    shader.setFloat(3, 0); // u_region_origin.y
    shader.setFloat(4, size.width * dpr); // u_region_size.x
    shader.setFloat(5, size.height * dpr); // u_region_size.y
    shader.setFloat(6, sigma * dpr); // u_sigma_max（物理像素）
    shader.setFloat(7, fadeStart); // u_fade_start
    shader.setFloat(8, curve); // u_curve
    shader.setFloat(9, axis); // u_axis：0 横向、1 纵向
    return ui.ImageFilter.shader(shader);
  }  LinearGradient _tint(double fadeStart, {double boost = 1.0}) {
    final base = SemColors.bg;
    final fade = fadeStart.clamp(0.0, 0.95);
    double a(double v) => (v * boost).clamp(0.0, 1.0);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        base.withValues(alpha: a(0.55)),
        base.withValues(alpha: a(0.38)),
        base.withValues(alpha: 0),
      ],
      stops: [0, fade, 1],
    );
  }
}

/// 顶栏渐进模糊 shader（两趟可分离高斯共用同一个 .frag）。
///
/// 启动时调用一次预热，避免第一帧顶栏临时编译 shader 造成卡顿；
/// 加载失败也没关系，[GlassBarScrim] 会自动退化到单层均匀模糊。
ui.FragmentProgram? _program;
bool _programFailed = false;

Future<void> preloadGlassTopBarShader() async {
  if (_program != null || _programFailed) return;
  try {
    _program = await ui.FragmentProgram.fromAsset(
      'packages/campus_core/shaders/glass_progressive_blur.frag',
    );
  } catch (_) {
    _programFailed = true;
  }
}