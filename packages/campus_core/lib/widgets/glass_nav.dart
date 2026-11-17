import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'theme_palette.dart';

/// 底栏条目：普通态 / 激活态图标 + 标签。
class GlassNavBarItem {
  const GlassNavBarItem(this.icon, this.activeIcon, this.label);

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// 液态玻璃底栏：thumb 可拖拽、带动量回弹（与 [GlassTabs] 同一物理）。
/// 页面区域横滑时由外壳通过 [dragPosition] 驱动同一个位置，两者不会打架。
class GlassNavBar extends StatefulWidget {
  const GlassNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.dragPosition,
    this.position,
  });

  final List<GlassNavBarItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  /// 页面区域横滑时外壳给的连续位置（单位 = 格：1.4 = 从第 2 格往第 3 格拖了 40%）。
  /// 非 null（拖动中）滑块直接跟手、不跑自己的弹簧；松手时外壳置回 null，
  /// 滑块从当前位置弹到落点（[index]）。
  final ValueListenable<double?>? dragPosition;

  /// 把「当前连续位置」写出来（每帧都写）：页面照着它位移，就能跟滑块**同一套弹簧**动，
  /// 切页时不会突兀地跳。弹簧本身仍藏在底栏里（谁都不用在别处再实现一遍物理）。
  final ValueNotifier<double>? position;

  @override
  State<GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<GlassNavBar> with SingleTickerProviderStateMixin {
  // unbounded：set value 不被默认 [0,1] 钳制，拖拽边界由自身 clamp 管理
  late final AnimationController _ctrl = AnimationController.unbounded(
      vsync: this, duration: const Duration(milliseconds: 600))
    ..value = widget.index.toDouble();
  int _target = -1;

  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 220, ratio: 0.75);

  void _springTo(double target, [double velocity = 0]) {
    _target = target.round();
    _ctrl.animateWith(SpringSimulation(_spring, _ctrl.value, target, velocity));
  }

  void _publish() => widget.position?.value = _ctrl.value;

  @override
  void initState() {
    super.initState();
    widget.dragPosition?.addListener(_onExternalDrag);
    _ctrl.addListener(_publish); // 所有位置变化都经过 _ctrl：弹簧、跟手、外部驱动
    _publish();
  }

  /// 外壳在页面区域拖动：非 null → 滑块跟手；置回 null（松手）→ 从当前位置弹到落点。
  void _onExternalDrag() {
    final v = widget.dragPosition!.value;
    if (v == null) {
      _springTo(widget.index.toDouble());
    } else {
      _ctrl.value = v.clamp(0.0, (widget.items.length - 1).toDouble());
    }
  }

  @override
  void didUpdateWidget(covariant GlassNavBar old) {
    super.didUpdateWidget(old);
    // 页面区域拖动中位置由外壳给，别在这儿再弹一次（会跟手指打架）
    if (widget.dragPosition?.value != null) return;
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
    final n = widget.items.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Container(
          height: 66,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            // 投影留在玻璃**外面**：里面那层要交给 ClipRRect 裁圆，裁完就画不出外投影了
            boxShadow: [
              BoxShadow(color: SemColors.shadow, offset: const Offset(0, 8), blurRadius: 24),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              // 毛玻璃底：把从底栏下面穿过去的页面内容糊掉，玻璃面再压在上面——
              // 底栏因此和内容分成两层，而不是一块和内容糊在一起的半透明色板
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: _face(n),
            ),
          ),
        ),
      ),
    );
  }

  /// 玻璃面：底下那层已经被外层 [BackdropFilter] 糊过，这里再压一层半透明面——
  /// 内容只透出模糊色块，字不会糊在玻璃上；透光度沿用玻璃卡面（card），与卡片同一档。
  Widget _face(int n) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(Colors.white.withValues(alpha: 0.10), SemColors.card),
              SemColors.card,
            ],
            stops: const [0, 0.5],
          ),
          border: Border.all(color: SemColors.border),
        ),
        child: LayoutBuilder(
          builder: (context, cons) {
            final segW = cons.maxWidth / n;
            final drag = widget.dragPosition;
            return AnimatedBuilder(
              animation: drag == null ? _ctrl : Listenable.merge([_ctrl, drag]),
              builder: (context, _) {
                // 页面区域拖动中滑块跟手（外壳给的位置）；否则用自身的弹簧位置
                final pos = (drag?.value ?? _ctrl.value).clamp(0.0, (n - 1).toDouble());
                final visual = pos.round().clamp(0, n - 1);
                return Stack(
                  children: [
                    Positioned(
                      left: pos * segW,
                      width: segW,
                      // 高度交给容器内区（66 − 边框 1×2 − 内边距 4×2 = 56），别写死：
                      // 原来 height: 58 比内区高 2px，超出部分被 Stack 的 Clip.hardEdge
                      // 从底部切平——滑块的下边框与下方两个圆角正好被切掉
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
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
                                color: SemColors.shadow,
                                offset: const Offset(0, 2),
                                blurRadius: 8),
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
                                // 段/秒；速度估计可能爆炸，先饱和
                                final v =
                                    (d.velocity.pixelsPerSecond.dx / segW).clamp(-8.0, 8.0);
                                // 慢速拖拽就近落段；快速甩动（flick）借动量多滑 1 段
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
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(widget.items[i].icon,
                                      size: 22,
                                      color: i == visual
                                          ? SemColors.accent
                                          : SemColors.textMuted),
                                  const SizedBox(height: 2),
                                  Text(widget.items[i].label,
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight:
                                            i == visual ? FontWeight.w600 : FontWeight.w500,
                                        color: i == visual
                                            ? SemColors.accent
                                            : SemColors.textMuted,
                                      )),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
      );
}
