import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 启动动画：把项目的 logo「画」出来。
///
/// 素材是 [split] 出来的三层（同一张 512 画布，各留本层像素），叠回去就是原标：
/// * `assets/sit-mark-dark.png` —— 深蓝弧（下半的「S」尾）
/// * `assets/sit-mark-light.png` —— 浅蓝弧（上半的「S」头）
/// * `assets/sit-mark-green.png` —— 绿节点（服务点位）
///
/// 播放顺序照 logo 自己的图形语言（浅蓝 / 深蓝对角断口 + 45° 锐角端头 + 绿点）：
/// 白底板弹入 → 深蓝弧顺时针扫出 → 浅蓝弧反向扫出并旋正 → 绿点弹落 → 字标上浮
/// → 转成呼吸 + 光环，直到首屏初始化跑完。
///
/// 约束：不能拖慢启动。动画是纯绘制（多边形裁剪 + 图片），没有模糊 / 滤镜 /
/// ShaderMask；初始化在后台异步跑，[BootPage] 至少让装配播完一轮再进主页。
class BootSplash extends StatefulWidget {
  const BootSplash({
    super.key,
    required this.stage,
    this.minShow = const Duration(milliseconds: 1400),
  });

  /// 当前阶段文案（「正在加载课表…」这类），由启动流程喂进来。
  final String stage;

  /// 至少播多久（太快会一闪而过，看不出是启动动画）。
  final Duration minShow;

  @override
  State<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<BootSplash> with TickerProviderStateMixin {
  /// 装配：一次性播放（底板 → 深蓝弧 → 浅蓝弧 → 绿点 → 字标）。
  late final AnimationController _assemble = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..forward();

  /// 装配完成后的循环：呼吸与光环。装配播完才开始，避免两段动画抢注意力。
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    _assemble.addStatusListener((s) {
      if (s == AnimationStatus.completed && !_loop.isAnimating) _loop.repeat();
    });
  }

  @override
  void dispose() {
    _assemble.dispose();
    _loop.dispose();
    super.dispose();
  }

  /// 某一段的进度（0 → 1）：装配播完停在 1，什么都没开始前停在 0。
  double _slice(double begin, double end) =>
      Interval(begin, end).transform(_assemble.value);

  @override
  Widget build(BuildContext context) {
    final dark = SemColors.isDark;
    return ColoredBox(
      color: SemColors.bg,
      child: Center(
        child: AnimatedBuilder(
          // 注意：所有时间相关的值必须在 builder 里算，不能提前到 build()
          // （否则只会按第一帧的值画一次，动画看起来没发生）。
          animation: Listenable.merge([_assemble, _loop]),
          builder: (context, _) {
            final plateT = Curves.easeOutBack.transform(_slice(0.0, 0.26));
            final wordT = Curves.easeOut.transform(_slice(0.68, 1.0));
            // 装配完才呼吸：整块 logo 1.0 → 1.035 → 1.0
            final breathe = 1 + math.sin(_loop.value * 2 * math.pi) * 0.035;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 240,
                  height: 240,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 光环：两圈错开扩散（装配完成后才显出来）
                      for (final offset in [0.0, 0.5])
                        if (_assemble.isCompleted || _loop.value > 0)
                          _pulseRing(offset, _slice(0.86, 1.0)),
                      Transform.scale(
                        scale: breathe,
                        child: SizedBox(
                          width: 136,
                          height: 136,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Transform.scale(
                                scale: plateT,
                                child: Container(
                                  // 测试据此量「动画真的在动」：图片解码是异步的，
                                  // 拿 Image 的 rect 量不到东西（未解码时尺寸恒为 0）。
                                  key: const ValueKey('boot-plate'),
                                  width: 136,
                                  height: 136,
                                  // 白底板：logo 是三色图形（浅蓝 + 深蓝 + 绿），压在深色底上
                                  // 会糊成一团；白圆角方块深浅色都衬得清，同桌面图标。
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(34),
                                    border: Border.all(
                                      color: dark
                                          ? Colors.white.withValues(alpha: 0.85)
                                          : SemColors.border,
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // 深蓝弧：从断口那一侧顺时针扫出来，同时旋正
                                    _sweepLayer(
                                      asset: 'assets/sit-mark-dark.png',
                                      begin: 0.06,
                                      end: 0.44,
                                      startAngle: -math.pi * 0.35,
                                      fromAngle: -0.26,
                                    ),
                                    // 浅蓝弧：晚一步、从另一侧扫，反向旋正（对角断口语言）
                                    _sweepLayer(
                                      asset: 'assets/sit-mark-light.png',
                                      begin: 0.20,
                                      end: 0.58,
                                      startAngle: -math.pi * 1.45,
                                      fromAngle: 0.26,
                                    ),
                                    // 绿点：最后一颗「服务点位」，弹落到位
                                    _greenDot(),
                                  ],
                                ),
                              ),
                              // 装配收尾：一道 45° 斜光扫过 logo（对应腰部那道斜断口）
                              _sheen(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Opacity(
                  opacity: wordT,
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - wordT)),
                    child: Text(
                      'AntiSIT',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 20,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    child: Text(
                      widget.stage,
                      key: ValueKey(widget.stage),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: SemColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 一层的「扫出」：用扇形裁剪，[sweep] 从 0 转到 1 = 整个扇区扫完一圈。
  ///
  /// 裁剪用多边形（几十个顶点），既有 45° 锐角的硬边观感，也没有着色器开销。
  Widget _sweepLayer({
    required String asset,
    required double begin,
    required double end,
    required double startAngle,
    required double fromAngle,
  }) {
    final p = Curves.easeInOutCubic.transform(_slice(begin, end));
    // 收尾留一点余量：p = 1 时扇区闭合，别让「已扫完」还留一条缝
    final sweep = p * (math.pi * 2.0);
    final rotate = fromAngle * (1 - p);
    return Opacity(
      opacity: math.min(1.0, p * 2.2),
      child: Transform.rotate(
        angle: rotate,
        child: Transform.scale(
          scale: 0.96 + 0.04 * p,
          child: ClipPath(
            clipper: _SweepClipper(sweep: sweep, startAngle: startAngle),
            child: Image.asset(asset, filterQuality: FilterQuality.medium),
          ),
        ),
      ),
    );
  }

  /// 收尾的斜光：一条 45° 的浅色窄带从左下扫到右上，扫完就消失。
  ///
  /// 用 [ClipRRect] + 渐变 [Container] 做，不用 ShaderMask / BackdropFilter。
  Widget _sheen() {
    final p = _slice(0.74, 1.0);
    if (p <= 0 || p >= 1) return const SizedBox.shrink();
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: SizedBox(
          width: 136,
          height: 136,
          child: Transform.translate(
            // 从右下角外沿走到左上角外沿
            offset: Offset(190 * (1 - p) - 95, 190 * (1 - p) - 95),
            child: Center(
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 34,
                  height: 320,
                  // 白底板上白色光带看不见：用一点强调色做「釉光」，只在白底上淡淡扫过
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        SemColors.accent.withValues(alpha: 0),
                        SemColors.accent.withValues(alpha: 0.16),
                        SemColors.accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 绿点：从 0 近回弹地放大到 1（「点位就位」那一下）。
  Widget _greenDot() {
    final t = Curves.elasticOut.transform(_slice(0.52, 0.84));
    return Opacity(
      opacity: _slice(0.50, 0.62).clamp(0.0, 1.0),
      child: Transform.scale(
        scale: t.clamp(0.0, 1.35),
        child: Image.asset(
          'assets/sit-mark-green.png',
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }

  /// 一圈向外扩散的光环；装配完成后循环播放。
  Widget _pulseRing(double offset, double assembled) {
    final p = ((_loop.value + offset) % 1.0);
    final s = 0.55 + p * 1.5;
    return IgnorePointer(
      child: Opacity(
        opacity: assembled,
        child: Container(
          width: 136 * s,
          height: 136 * s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                SemColors.accent.withValues(alpha: (1 - p) * 0.22),
                SemColors.accent.withValues(alpha: 0),
              ],
            ),
            border: Border.all(
              color: SemColors.accent.withValues(alpha: (1 - p) * 0.30),
              width: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// 从中心出发、按 [sweep] 弧度铺开的多边形扇区（用作「扫出」裁剪）。
class _SweepClipper extends CustomClipper<Path> {
  _SweepClipper({required this.sweep, required this.startAngle});

  /// 已扫过的弧度（0 → 2π）。
  final double sweep;

  /// 起始角（弧度，0 = 指向右侧，顺时针为正）。
  final double startAngle;

  @override
  Path getClip(Size size) {
    final center = size.center(Offset.zero);
    final radius = size.longestSide * 0.78;
    final path = Path()..moveTo(center.dx, center.dy);
    // 顶点数：扫得越多给得越密，保证弧线边缘看起来是圆的
    final steps = math.max(3, (sweep / (math.pi * 2) * 120).ceil());
    for (var i = 0; i <= steps; i++) {
      final a = startAngle + sweep * (i / steps);
      path.lineTo(
        center.dx + radius * math.cos(a),
        center.dy + radius * math.sin(a),
      );
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_SweepClipper old) =>
      old.sweep != sweep || old.startAngle != startAngle;
}