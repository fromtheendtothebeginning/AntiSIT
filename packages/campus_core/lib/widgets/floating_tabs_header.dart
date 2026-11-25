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

  /// 已经挂过一次「帧末重建」回调（同一帧里翻来覆去只挂一次）。
  bool _rebuildScheduled = false;

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
    if (widget.dragPosition?.value != null) _setHidden(false);
  }

  /// 收起 / 展开状态**只能延到帧末再重建**。
  ///
  /// 滚动通知是在 layout 阶段派发的（列表在 `performLayout` 里同步发出通知），
  /// 回调里直接 `setState` 等于「在布局过程中给本帧再排一次构建」：页面里只要有
  /// [LayoutBuilder]（切换器自己就有一个），就会撞上框架断言
  /// `_RenderLayoutBuilder was mutated in ...performLayout` /
  /// `'debugNeedsLayout': is not true` / `Build scheduled during frame`——
  /// 真机上的红屏就是这么来的。挪到帧末只多一帧，肉眼看不出来。
  void _setHidden(bool value) {
    if (_hidden == value) return;
    _hidden = value;
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  bool _onScroll(ScrollNotification n) {
    // **只认本页竖列表的滚动**。这里曾经有个「横向滚动 = PageView 在切页」的分支，
    // PageView 换成自管位置之后它就是死代码，而且会误伤：页面里的搜索框
    // （TextField 内部的 EditableText 本身就是横向可滚动的）一滚动就会把
    // `pixels / viewportDimension` 写进 dragPosition，让两页跟着这个伪位置平移、
    // 松手再弹回来——正是 issue #11「滑到顶部时两页自己跳一下又回来」。
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is! ScrollUpdateNotification) return false;
    final metrics = n.metrics;
    // 到顶（含下拉回弹）一律展开
    if (metrics.pixels <= 0) {
      _setHidden(false);
      return false;
    }
    final delta = n.scrollDelta ?? 0;
    if (delta > _slop) {
      _setHidden(true); // 往下看内容 → 收起
    } else if (delta < -_slop) {
      _setHidden(false); // 往回翻 → 展开
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
            // 这层裁剪是必须的：收起走的是 AnimatedSlide（paint 期 transform），布局位置没变，
            // Stack 自己的 clipBehavior 只在「子节点布局溢出」时才建裁剪层，管不住它。
            // 没有这层时，**关掉悬浮顶栏**（topInset=0、切换器自身只剩 48 高）会让药丸
            // 只上移约 50px，正好停在状态栏 + 标题栏那一条里浮在标题上面（issue #10）；
            // 裁到自己的盒子里，收起的药丸就彻底出画。
            child: ClipRect(
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
        ),
      ],
    );
  }
}
