import 'package:flutter/material.dart';

import 'theme_palette.dart';

/// 带「悬浮分段切换器」的页面容器：切换器钉在玻璃顶栏下方，页面下滑时收起、上滑时展开。
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

  /// 页面内容（通常是 PageView / 列表），它的滚动通知用来决定收起 / 展开。
  final Widget child;

  /// 横滑切页时的连续位置（单位 = 段）；非 null 也代表页面正在横滑，收起中的切换器会因此展开。
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

  /// 方向死区：单帧位移小于它不算切换（手指轻微抖动不触发）。
  static const double _slop = 2.0;

  bool _hidden = false;

  /// 已经挂过一次「帧末重建」回调（同一帧里只挂一次）。
  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.dragPosition?.addListener(_onPageDrag);
  }

  @override
  void dispose() {
    widget.dragPosition?.removeListener(_onPageDrag);
    super.dispose();
  }

  /// 页面开始横滑时展开切换器。
  void _onPageDrag() {
    if (widget.dragPosition?.value != null) _setHidden(false);
  }

  /// 收起 / 展开只能延到帧末再重建：滚动通知在 layout 阶段派发，
  /// 回调里直接 setState 会撞上「Build scheduled during frame」断言。
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

  /// 只认本页竖列表的滚动；横向滚动（如搜索框内部）不参与收起判断。
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is! ScrollUpdateNotification) return false;
    final metrics = n.metrics;
    // 到顶（含下拉回弹）一律展开。
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
            // 收起后不拦触摸：这块区域要让给列表。
            ignoring: _hidden,
            // 这层裁剪是必须的：AnimatedSlide 只在 paint 期位移，Stack 的 clipBehavior
            // 管不住；没有它，收起后切换器会停在状态栏 + 标题栏那一条里。
            child: ClipRect(
              child: AnimatedSlide(
                offset: Offset(0, _hidden ? _hiddenOffset : 0),
                duration: widget.showDuration,
                curve: Curves.easeOutCubic,
                // 底部留白放在毛玻璃外面：否则模糊会拖到切换器下面那条空隙里。
                child: Padding(
                  padding: EdgeInsets.only(top: widget.topInset, bottom: 8),
                  // 左右留白和页面内容对齐（内容列表都是 12）。
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(_radius),
                      // 和首页底栏同一套玻璃面（不做实时模糊，见 issue #20）。
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
                                SemColors.card,
                              ),
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
