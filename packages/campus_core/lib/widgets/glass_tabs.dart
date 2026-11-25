import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'theme_palette.dart';

/// 「外观」滑块的连续位置 → 整站该暗到什么程度（0 = 全浅、1 = 全深）。
/// 位置 0 跟随系统深浅、1 浅色、2 深色；中间值线性插值，静止时正好等于该档，松手不跳色。
double appearanceDarkness(double pos, {required bool systemDark}) {
  if (pos >= 1) return (pos - 1).clamp(0.0, 1.0);
  final base = systemDark ? 1.0 : 0.0;
  return base * (1 - pos).clamp(0.0, 1.0);
}

/// 液态玻璃滑块 Tab：玻璃轨道 + 等宽分栏，thumb 可拖拽并带弹簧动量，点击同样滑过去。
class GlassTabs extends StatefulWidget {
  const GlassTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.height = 34,
    this.fontSize = 12.5,
    this.position,
    this.dragPosition,
    this.flat = false,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final double height;
  final double fontSize;

  /// 把「当前连续位置」写出来（每帧，单位 = 段）：调用方据此做实时配色或联动内容。
  final ValueNotifier<double>? position;

  /// 页面区域横滑时调用方驱动同一位置：非 null（拖动中）跟手，置回 null（松手）弹到落点。
  final ValueListenable<double?>? dragPosition;

  /// 去掉自身的底板与描边（外层已有玻璃胶囊时用）。
  final bool flat;

  @override
  State<GlassTabs> createState() => _GlassTabsState();
}

class _GlassTabsState extends State<GlassTabs> with SingleTickerProviderStateMixin {
  // unbounded：set value 不被默认 [0,1] 钳制，拖拽边界由自身 clamp 管理。
  late final AnimationController _ctrl = AnimationController.unbounded(
      vsync: this, duration: const Duration(milliseconds: 600))
    ..value = widget.index.toDouble();
  int _target = -1;

  /// 欠阻尼弹簧：轻微过冲的回弹手感。
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 260, ratio: 0.72);

  /// 弹到目标段（可带初速度）。
  void _springTo(double target, [double velocity = 0]) {
    _target = target.round();
    _ctrl.animateWith(SpringSimulation(_spring, _ctrl.value, target, velocity));
  }

  void _publish() => widget.position?.value = _ctrl.value;

  /// 调用方在页面区域拖动：非 null → 滑块跟手；置回 null（松手）→ 从当前位置弹到落点。
  void _onExternalDrag() {
    final v = widget.dragPosition!.value;
    if (v == null) {
      _springTo(widget.index.toDouble());
    } else {
      _ctrl.value = v.clamp(0.0, (widget.labels.length - 1).toDouble());
    }
  }

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_publish); // 所有位移都经过 _ctrl：弹簧、跟手、外部驱动
    widget.dragPosition?.addListener(_onExternalDrag);
    _publish();
  }

  @override
  void didUpdateWidget(covariant GlassTabs old) {
    super.didUpdateWidget(old);
    // 页面区域拖动中位置由调用方给，别在这儿又弹一次（会跟手指打架）。
    if (widget.dragPosition?.value != null) return;
    // 自身触发的回调已在动量动画中，不重启。
    if (old.index != widget.index && widget.index != _target) {
      _springTo(widget.index.toDouble());
    }
  }

  @override
  void dispose() {
    widget.dragPosition?.removeListener(_onExternalDrag);
    _ctrl.removeListener(_publish);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.labels.length;
    return Container(
      padding: widget.flat ? EdgeInsets.zero : const EdgeInsets.all(3),
      decoration: widget.flat
          ? null
          : BoxDecoration(
              color: SemColors.cardElevated,
              borderRadius: BorderRadius.circular(widget.height / 2 + 3),
              border: Border.all(color: SemColors.border),
            ),
      child: LayoutBuilder(
        builder: (context, cons) {
          final segW = cons.maxWidth / n;
          final drag = widget.dragPosition;
          return SizedBox(
            height: widget.height,
            child: AnimatedBuilder(
              animation: drag == null ? _ctrl : Listenable.merge([_ctrl, drag]),
              builder: (context, _) {
                // 页面区域拖动中滑块跟手（调用方给的位置）；否则用自身的弹簧位置。
                final pos = (drag?.value ?? _ctrl.value).clamp(0.0, (n - 1).toDouble());
                final visual = pos.round().clamp(0, n - 1);
                return Stack(
                  children: [
                    Positioned(
                      left: pos * segW,
                      width: segW,
                      top: 0,
                      height: widget.height,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(widget.height / 2),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color.alphaBlend(
                                  Colors.white.withValues(alpha: 0.25), SemColors.thumb),
                              SemColors.thumb,
                            ],
                          ),
                          border: Border.all(color: SemColors.borderStrong),
                          boxShadow: [
                            BoxShadow(
                                color: SemColors.shadow, offset: const Offset(0, 2), blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < n; i++)
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (i != widget.index) {
                                  _springTo(i.toDouble());
                                  HapticFeedback.selectionClick();
                                  widget.onChanged(i);
                                }
                              },
                              onHorizontalDragStart: (_) => _ctrl.stop(),
                              onHorizontalDragUpdate: (d) =>
                                  _ctrl.value = (_ctrl.value + d.primaryDelta! / segW)
                                      .clamp(0.0, (n - 1).toDouble()),
                              onHorizontalDragEnd: (d) {
                                // 速度按「段/秒」，并先饱和，避免估计值爆炸。
                                final v =
                                    (d.velocity.pixelsPerSecond.dx / segW).clamp(-8.0, 8.0);
                                // 慢速拖拽就近落段；快速甩动（flick）借动量多滑 1 段。
                                var target = _ctrl.value.round().clamp(0, n - 1);
                                final next = target + (v > 0 ? 1 : -1);
                                if (v.abs() >= 5.0 && next >= 0 && next <= n - 1) {
                                  target = next;
                                }
                                _springTo(target.toDouble(), v);
                                if (target != widget.index) {
                                  HapticFeedback.selectionClick();
                                  widget.onChanged(target);
                                }
                              },
                              child: Center(
                                child: Text(
                                  widget.labels[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: widget.fontSize,
                                    fontWeight: i == visual ? FontWeight.w600 : FontWeight.w500,
                                    color:
                                        i == visual ? SemColors.textPrimary : SemColors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
