import 'dart:ui';

import 'package:flutter/material.dart';

import 'theme_palette.dart';

/// 带「悬浮分段切换器」的页面容器：把切换器钉在玻璃顶栏下方，
/// 页面**向下滑动**（继续看内容）时自动收起藏到顶栏底下，**向上滑动**时重新展开。
///
/// 用滚动通知判断方向，不依赖各页自己的 ScrollController——PageView 里两页各有
/// 一条列表，这样不用为每条列表都挂控制器，也不会因为换页而丢监听。
///
/// 用法：
/// ```dart
/// body: GlassFadedBody(
///   barHeight: topInset,
///   child: FloatingTabsHeader(
///     topInset: topInset,
///     header: _tabsRow(),
///     child: PageView(...),
///   ),
/// )
/// ```
class FloatingTabsHeader extends StatefulWidget {
  const FloatingTabsHeader({
    super.key,
    required this.topInset,
    required this.header,
    required this.child,
    this.dragPosition,
    this.showDuration = const Duration(milliseconds: 200),
  });

  /// 悬浮玻璃顶栏占的高度（切换器就从这下面开始排）。
  final double topInset;

  /// 切换器本体（通常是 `GlassTabs(flat: true, ...)`）。
  final Widget header;

  /// 页面内容（通常是 PageView / 列表）。它的滚动通知用来决定收起 / 展开。
  final Widget child;

  /// 横滑切页时把「当前连续位置」写出去（单位 = 段，1.5 = 第 2、3 段中间），
  /// 切换器据此实时跟手；置回 null（松手）时切换器自己弹到落点。
  /// 非 null 也代表「页面正在横滑」，收起中的切换器会因此展开。
  final ValueNotifier<double?>? dragPosition;

  /// 收起 / 展开的动画时长。
  final Duration showDuration;

  @override
  State<FloatingTabsHeader> createState() => _FloatingTabsHeaderState();
}

class _FloatingTabsHeaderState extends State<FloatingTabsHeader> {
  /// 收起状态下的位移（相对自身高度）：-1 就整个移出屏幕。
  static const double _hiddenOffset = -1.05;

  /// 玻璃胶囊的圆角（与首页底栏一致）。
  static const double _radius = 22;

  /// 方向死区：单帧位移小于这个值先生效（手指轻微抖动不切换）。
  static const double _slop = 2.0;

  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    // 页面横滑（自管手势，不走滚动通知）开始时 dragPosition 会从 null 变非 null：
    // 借这个信号把收起中的切换器展开，保证「换页时看得见切换器」。
    widget.dragPosition?.addListener(_onPageDrag);
  }

  @override
  void dispose() {
    widget.dragPosition?.removeListener(_onPageDrag);
    super.dispose();
  }

  void _onPageDrag() {
    if (widget.dragPosition?.value != null && _hidden) {
      setState(() => _hidden = false);
    }
  }

  bool _onScroll(ScrollNotification n) {
    // 横向滚动 = PageView 在切页
    if (n.metrics.axis == Axis.horizontal) {
      // 用户正在换页面：切换器要展开（收起状态下横滑换页也得看得见它）
      if (_hidden) setState(() => _hidden = false);
      // 把连续位置写给切换器：拖动页面时滑块实时跟随（默认行为，不受开关控制）。
      // 松手（ScrollEnd）置空，让切换器自己弹到落点。
      final drag = widget.dragPosition;
      if (drag != null) {
        if (n is ScrollEndNotification) {
          drag.value = null;
        } else {
          final m = n.metrics;
          final pos = m.viewportDimension <= 0
              ? 0.0
              : (m.pixels / m.viewportDimension);
          drag.value = pos.clamp(0.0, double.infinity);
        }
      }
      return false;
    }
    if (n is! ScrollUpdateNotification) return false;
    final metrics = n.metrics;
    // 到顶（含下拉回弹）一律展开
    if (metrics.pixels <= 0) {
      if (_hidden) setState(() => _hidden = false);
      return false;
    }
    final delta = n.scrollDelta ?? 0;
    if (delta > _slop && !_hidden) {
      setState(() => _hidden = true); // 往下看内容 → 收起
    } else if (delta < -_slop && _hidden) {
      setState(() => _hidden = false); // 往回翻 → 展开
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            // 收起后不拦触摸：这块区域要让给列表
            ignoring: _hidden,
            child: AnimatedSlide(
              offset: Offset(0, _hidden ? _hiddenOffset : 0),
              duration: widget.showDuration,
              curve: Curves.easeOutCubic,
              // 底部留白放在毛玻璃**外面**：否则模糊会拖到切换器下面那条空隙里
              child: Padding(
                padding: EdgeInsets.only(top: widget.topInset, bottom: 8),
                // 左右留白和页面内容对齐（内容列表都是 12），别贴屏幕边
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_radius),
                    child: BackdropFilter(
                      // 和首页底栏同一套毛玻璃：把从切换器底下滚过去的内容糊掉
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      // 再压一层半透明玻璃面 + 描边（同 GlassNavBar 的 _face）
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(_radius),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color.alphaBlend(
                                  Colors.white.withValues(alpha: 0.10),
                                  SemColors.card),
                              SemColors.card,
                            ],
                            stops: const [0, 0.5],
                          ),
                          border: Border.all(color: SemColors.border),
                        ),
                        child: widget.header,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
