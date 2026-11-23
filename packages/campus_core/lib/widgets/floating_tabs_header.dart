import 'package:flutter/material.dart';

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
    this.showDuration = const Duration(milliseconds: 200),
  });

  /// 悬浮玻璃顶栏占的高度（切换器就从这下面开始排）。
  final double topInset;

  /// 切换器本体（通常是 GlassTabs）。
  final Widget header;

  /// 页面内容（通常是 PageView / 列表）。它的滚动通知用来决定收起 / 展开。
  final Widget child;

  /// 收起 / 展开的动画时长。
  final Duration showDuration;

  @override
  State<FloatingTabsHeader> createState() => _FloatingTabsHeaderState();
}

class _FloatingTabsHeaderState extends State<FloatingTabsHeader> {
  /// 收起状态下的位移（相对自身高度）：-1 就整个移出屏幕。
  static const double _hiddenOffset = -1.05;

  /// 方向死区：单帧位移小于这个值先生效（手指轻微抖动不切换）。
  static const double _slop = 2.0;

  bool _hidden = false;

  bool _onScroll(ScrollNotification n) {
    if (n is! ScrollUpdateNotification) return false;
    // 只看竖向滚动：PageView 自己切换页时也会发横向滚动通知，
    // 不过滤的话「点一下切换器」就会被当成向下滑动，把切换器收起。
    if (n.metrics.axis != Axis.vertical) return false;
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
              child: Padding(
                padding: EdgeInsets.only(top: widget.topInset),
                child: widget.header,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
