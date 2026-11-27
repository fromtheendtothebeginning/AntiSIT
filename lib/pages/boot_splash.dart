import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 启动动画：校徽呼吸 + 光晕扩散 + 进度文案，等首屏初始化跑完再淡出。
///
/// 设计约束：不能拖慢启动——动画本身是纯绘制（没有模糊 / 滤镜），初始化在后台
/// 异步跑，[BootPage] 至少让动画播完一轮（约 [minShow]），之后立即切主页。
class BootSplash extends StatefulWidget {
  const BootSplash({
    super.key,
    required this.stage,
    this.minShow = const Duration(milliseconds: 1200),
  });

  /// 当前阶段文案（「正在加载课表…」这类），由启动流程喂进来。
  final String stage;

  /// 至少播多久（太快会一闪而过，看不出是启动动画）。
  final Duration minShow;

  @override
  State<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<BootSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = SemColors.isDark;
    return ColoredBox(
      color: SemColors.bg,
      child: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            // 一圈 = 2.4s：0→0.5 放大淡出，0.5→1 收拢，作为下一圈的起点。
            final phase = (t * 2) % 1.0;
            final ringScale = 0.6 + phase * 1.6;
            final ringAlpha = (1 - phase) * 0.55;
            // 校徽呼吸：1.0 → 1.06 → 1.0
            final breathe = 1 + math.sin(t * 2 * math.pi) * 0.03;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 扩散光晕：两圈错开，避免只有一圈时显得单薄
                      for (final offset in [0.0, 0.5])
                        Builder(
                          builder: (context) {
                            final p = ((t * 2 + offset) % 1.0);
                            final s = 0.6 + p * 1.6;
                            return Container(
                              width: 120 * s,
                              height: 120 * s,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    SemColors.accent.withValues(
                                      alpha: (1 - p) * 0.28,
                                    ),
                                    SemColors.accent.withValues(alpha: 0),
                                  ],
                                ),
                                border: Border.all(
                                  color: SemColors.accent.withValues(
                                    alpha: (1 - p) * 0.35,
                                  ),
                                  width: 1,
                                ),
                              ),
                            );
                          },
                        ),
                      Transform.scale(
                        scale: breathe,
                        child: Container(
                          width: 96,
                          height: 96,
                          // 底板固定白：校徽是深蓝 + 浅蓝 + 绿的双色图形，压在深色半透面上
                          // 会糊成一团；白色圆角方块在深浅色下都能把它衬清楚（同桌面图标）。
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: dark
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : SemColors.border,
                            ),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Image.asset('assets/sit-mark.png'),
                        ),
                      ),
                      // ringScale / ringAlpha 保留给以后的方框描边动画用
                      IgnorePointer(
                        child: SizedBox(
                          width: 120 * ringScale,
                          height: 120 * ringScale,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: SemColors.accent.withValues(
                                  alpha: ringAlpha,
                                ),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'AntiSIT',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
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
}
