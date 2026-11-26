import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'flexible_grid_card.dart';
import 'flexible_grid_drag.dart';
import 'flexible_grid_edge_scroll.dart';
import 'flexible_grid_size.dart';

// 尺寸模型 / 拖拽缩放 / 位移动画 / 绘制器 / 卡片外观 / 边缘滚动拆到同目录文件，
// 这里 re-export 保持原入口可见。
export 'card_size_bar.dart';
export 'flexible_grid_card.dart';
export 'flexible_grid_drag.dart';
export 'flexible_grid_edge_scroll.dart';
export 'flexible_grid_motion.dart';
export 'flexible_grid_painters.dart';
export 'flexible_grid_size.dart';

/// 卡片内容构造器：页面按尺寸与是否整理中做不同排版。
typedef FlexibleCardBuilder =
    Widget Function(BuildContext context, GridCardSize size, bool editing);

/// [FlexibleCardGrid] 里的一张卡片：id 用来认人 / 落盘，size 是当前占位。
@immutable
class FlexibleGridItem {
  const FlexibleGridItem({
    required this.id,
    required this.size,
    required this.builder,
  });

  final String id;
  final GridCardSize size;
  final FlexibleCardBuilder builder;

  FlexibleGridItem withSize(GridCardSize value) =>
      FlexibleGridItem(id: id, size: value, builder: builder);
}

/// 可整理（长按拖动换位 / 尺寸切换条 / 拖右下角弧线连续缩放）的柔性宫格。
/// 手势三段式互不冲突：长按 = 只拖动换位，松手 = 进整理态并选中，整理态点选 / 拖弧线 = 只改尺寸。
class FlexibleCardGrid extends StatefulWidget {
  const FlexibleCardGrid({
    super.key,
    required this.items,
    required this.editing,
    required this.onEditingChanged,
    required this.onOrderChanged,
    required this.onSizeChanged,
    this.selectedId,
    this.onSelected,
    this.padding = EdgeInsets.zero,
    this.spacing = 10,
    this.unitHeight = 59,
    this.autoScrollEdge = 72,
  });

  final List<FlexibleGridItem> items;

  /// 是否处于整理状态：显示缩放手柄、卡片可立即拖动。
  final bool editing;

  /// 进入 / 退出整理状态（长按卡片、点空白处时回调）。
  final ValueChanged<bool> onEditingChanged;

  /// 拖拽落位后的新顺序（按卡片 id），仅在顺序真的变了时回调。
  final ValueChanged<List<String>> onOrderChanged;

  /// 缩放落位后的新尺寸，仅在尺寸真的变了时回调。
  final void Function(String id, GridCardSize size) onSizeChanged;

  /// 当前选中的卡片：尺寸条作用于它，也只有它显示缩放弧线；null 时每张都显示。
  final String? selectedId;

  /// 长按 / 整理态点卡片 / 开始拖拽时，把用户想操作的卡片报给调用方。
  final ValueChanged<String>? onSelected;

  /// 四周留白（宫格自己算列宽用，调用方的滚动容器不要再加同方向内边距）。
  final EdgeInsets padding;

  /// 卡片间距（横竖同值）。
  final double spacing;

  /// 基础行高：2 行 + 1 个间距就是默认卡片高度（128dp）。
  final double unitHeight;

  /// 拖动时距滚动区上下边缘多少像素内开始自动滚动。
  final double autoScrollEdge;

  @override
  State<FlexibleCardGrid> createState() => _FlexibleCardGridState();
}

class _FlexibleCardGridState extends State<FlexibleCardGrid>
    with SingleTickerProviderStateMixin {
  static const double _maxEdgeScrollSpeed = 900; // px/s

  /// 换尺寸的过渡时长（比换位慢，卡片像被轻轻推着长开 / 收回）。
  static const Duration _sizeAnim = Duration(milliseconds: 520);

  /// 只是换位置的过渡（邻居让位）：短一点，避免整页跟着「飘」。
  static const Duration _moveAnim = Duration(milliseconds: 300);

  /// 拖出去多远才算「真的挪开」：低于它时邻居不让位，避免轻轻一碰就整页重排。
  static const double _moveAwayThreshold = 14;

  /// 缩放起手的死区：位移小于它不缩放（防手抖）。
  static const double _resizeDeadZone = 3;

  /// 整个排版区的 RenderBox：把手指的全局坐标换算成宫格坐标。
  final GlobalKey _stackKey = GlobalKey();

  /// 最近的竖向滚动容器（拖到边缘要自己滚）。
  ScrollPosition? _scrollPos;

  /// 拖动中：卡片悬在手指下，落点在它正下方留一块空位。
  GridDragState? _drag;

  /// 缩放中：手柄跟手，尺寸连续变化，松手吸附到最近档位。
  GridResizeState? _resize;

  /// 刚落位、还在等 store 回写的新顺序 / 新尺寸。
  final GridPendingChanges _pending = GridPendingChanges();

  /// 上一次 build 的几何：手势回调里要用它算「按在哪个卡片上」。
  double _colWidth = 0;
  List<GridPlacement> _placements = const [];

  /// 上一帧每张卡的像素尺寸：判断这次是「换位置」还是「卡框要长 / 要收」。
  Map<String, Size> _lastSizes = const {};

  /// 边缘自动滚动（只在拖动中跑）。
  late final GridEdgeScroller _edgeScroller;

  /// 当前几何换算：档位 ↔ 像素尺寸。
  GridCardMetrics get _metrics => GridCardMetrics(
        colWidth: _colWidth,
        unitHeight: widget.unitHeight,
        gap: widget.spacing,
      );

  /// 当前排版器：网格装箱 + 占位格换算。
  GridLayout get _layout => GridLayout(metrics: _metrics, padding: widget.padding);

  @override
  void initState() {
    super.initState();
    _edgeScroller = GridEdgeScroller(
      vsync: this,
      edge: widget.autoScrollEdge,
      maxSpeed: _maxEdgeScrollSpeed,
      onScrolled: () => setState(() {}),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollPos = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
  }

  @override
  void didUpdateWidget(covariant FlexibleCardGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = {for (final item in widget.items) item.id};
    if (!widget.editing && oldWidget.editing) {
      // 页面点了「完成」：拖动 / 缩放一起收掉。
      _edgeScroller.stop();
      _drag = null;
      _resize = null;
    }
    if (_drag != null && !ids.contains(_drag!.itemId)) _drag = null;
    if (_resize != null && !ids.contains(_resize!.itemId)) _resize = null;
    if (_drag == null) _edgeScroller.stop();
    _pending.settle(widget.items);
  }

  @override
  void dispose() {
    _edgeScroller.dispose();
    super.dispose();
  }

  /// 不拖动、不缩放时的基准顺序 / 尺寸：调用方数据 + 尚未回写的本地覆盖。
  List<FlexibleGridItem> _baseItems() => _pending.applyTo(widget.items);

  /// 真正参与排版的卡片：被拖动 / 正在缩放的那张不在流里，只留一个占位背景。
  List<FlexibleGridItem> _displayItems() {
    var items = _baseItems();
    final drag = _drag;
    if (drag != null) {
      items = [
        for (final item in items)
          if (item.id != drag.itemId) item,
      ];
    }
    final resize = _resize;
    if (resize != null) {
      items = [
        for (final item in items)
          if (item.id != resize.itemId) item,
      ];
    }
    return items;
  }

  /// 当前要占住的格位：拖动时是落点（还没拖开时是起手位），缩放时是自己的槽位。
  GridReservation? _reservedSlot() {
    final drag = _drag;
    if (drag != null) {
      final origin = GridReservation(
        row: drag.originRow,
        col: drag.originCol,
        size: drag.size,
      );
      if (!drag.movedAway) return origin;
      final drop = _dropPoint(drag);
      if (drop == null) return origin;
      return _layout.slotForDrop(drag, drop, _baseItems());
    }

    // 缩放中：占住自己的槽位，尺寸取「排斥用的尺寸」（缩小按最近档，放大按装得下的档）。
    final resize = _resize;
    if (resize != null) {
      return GridReservation(
        row: resize.originRow,
        col: resize.originCol,
        size: resize.reserve,
      );
    }
    return null;
  }

  /// 拖动的落点（宫格本地坐标 = 悬浮卡片的中心，不用指尖，避免插入判定与视觉错位）。
  Offset? _dropPoint(GridDragState drag) {
    final local = _toLocal(drag.pointer);
    if (local == null) return null;
    final topLeft = local - drag.grab;
    return topLeft + drag.sizePx.center(Offset.zero);
  }

  Offset? _toLocal(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.globalToLocal(global);
  }

  GridPlacement? _hitTest(Offset local) {
    // 后画的在上面：从后往前找，拖动中的卡片盖住别人时也先命中它。
    for (final p in _placements.reversed) {
      if (p.rect.contains(local)) return p;
    }
    return null;
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (_drag != null || _resize != null) return;
    final local = _toLocal(details.globalPosition);
    if (local == null) return;
    final hit = _hitTest(local);
    if (hit == null) return; // 长按在空白 / 卡片缝隙里：不进整理。
    if (!widget.editing) widget.onEditingChanged(true);
    HapticFeedback.mediumImpact();
    _beginDrag(hit.item, hit.rect, details.globalPosition);
  }

  void _onLongPressMove(LongPressMoveUpdateDetails details) =>
      _updateDrag(details.globalPosition);

  void _onLongPressEnd(LongPressEndDetails _) => _endDrag();

  void _onLongPressCancel() => _cancelDrag();

  void _beginDrag(FlexibleGridItem item, Rect rect, Offset global) {
    final local = _toLocal(global);
    if (local == null) return;
    widget.onSelected?.call(item.id);
    // 起手格位：用当前排版里这张卡的位置反推（它此刻一定在 placements 里）。
    final placement = _placements
        .where((p) => p.item.id == item.id)
        .firstOrNull;
    setState(() {
      _resize = null;
      _drag = GridDragState(
        itemId: item.id,
        item: item,
        size: item.size,
        sizePx: rect.size,
        grab: local - rect.topLeft,
        pointer: global,
        origin: rect,
        originRow: placement?.row ?? 0,
        originCol: placement?.col ?? 0,
      );
    });
    _syncEdgeScroll();
  }

  /// 长按拖动只换位置：卡片悬在手指下，落点格位由 [_reservedSlot] 占住。
  void _updateDrag(Offset global) {
    final drag = _drag;
    if (drag == null) return;
    final movedAway = (global - drag.startPointer).distance >= _moveAwayThreshold;
    if (movedAway == drag.movedAway && drag.pointer == global) return;
    if (movedAway && !drag.movedAway) HapticFeedback.selectionClick();
    setState(() {
      drag.pointer = global;
      drag.movedAway = movedAway;
    });
    _syncEdgeScroll();
  }

  /// 松手：顺序落位并停在整理态选中这张卡（可以接着改大小）。
  void _endDrag() {
    final drag = _drag;
    if (drag == null) return;
    _edgeScroller.stop();

    // 没拖开就松手 = 纯长按：必须保持原顺序。
    final baseIds = [for (final item in _baseItems()) item.id];
    final movedAway = drag.movedAway;
    final local = movedAway ? _dropPoint(drag) : null;
    final others = _displayItems(); // 已经不含被拖的那张
    final insertAt = local == null
        ? -1
        : _layout.dropIndexFor(
            local,
            _baseItems().where((i) => i.id != drag.itemId).toList(),
          );
    final ids = <String>[
      if (insertAt < 0)
        ...baseIds
      else ...[
        for (var i = 0; i < others.length; i++) ...[
          if (i == insertAt) drag.itemId,
          others[i].id,
        ],
        if (insertAt >= others.length) drag.itemId,
      ],
    ];

    final changed = !gridSameOrder(ids, baseIds);
    setState(() {
      _drag = null;
      if (changed) _pending.order = List<String>.of(ids);
    });
    if (changed) {
      widget.onOrderChanged(ids);
      HapticFeedback.lightImpact();
    }
    // 顺序：先进整理态再选中 —— 反过来会被页面的「进整理自动选第一张」覆盖掉。
    if (!widget.editing) widget.onEditingChanged(true);
    widget.onSelected?.call(drag.itemId);
  }

  void _cancelDrag() {
    if (_drag == null) return;
    _edgeScroller.stop();
    setState(() => _drag = null);
  }

  void _startResize(FlexibleGridItem item, Offset global) {
    if (_drag != null || _resize != null) return;
    final placement = _placements
        .where((p) => p.item.id == item.id)
        .firstOrNull;
    if (placement == null) return;
    widget.onSelected?.call(item.id);
    setState(() {
      _drag = null;
      _resize = GridResizeState(
        itemId: item.id,
        start: item.size,
        startPx: placement.rect.size,
        startPointer: global,
        originRow: placement.row,
        originCol: placement.col,
      );
    });
    HapticFeedback.selectionClick();
  }

  /// 跟手缩放：位移直接加到起手像素尺寸上，算出最近档位背景；卡框本体钉在起手格位。
  void _updateResize(Offset global) {
    final resize = _resize;
    if (resize == null) return;
    final delta = global - resize.startPointer;
    if (!resize.started) {
      if (delta.distance < _resizeDeadZone) return;
      resize.started = true;
    }
    // 连续像素尺寸：宽高各自跟手，并夹在设计档位的范围内。
    final minW = _colWidth;
    final maxW = 3 * _colWidth + 2 * widget.spacing;
    final minH = widget.unitHeight;
    final maxH = 2 * widget.unitHeight + widget.spacing;
    final width = (resize.startPx.width + delta.dx).clamp(minW, maxW);
    final height = (resize.startPx.height + delta.dy).clamp(minH, maxH);
    final nextPx = Size(width, height);
    final snapped = _metrics.nearestPreset(nextPx);
    final reserve = _metrics.reserveFor(nextPx, resize.start);
    if (nextPx == resize.currentPx &&
        snapped == resize.snapped &&
        reserve == resize.reserve) {
      return;
    }
    if (snapped != resize.snapped) HapticFeedback.selectionClick();
    setState(() {
      resize.currentPx = nextPx;
      resize.snapped = snapped;
      resize.reserve = reserve;
    });
  }

  void _endResize() {
    final resize = _resize;
    if (resize == null) return;
    final target = resize.snapped;
    final changed = target != resize.start;
    setState(() {
      _resize = null;
      if (changed) _pending.sizes[resize.itemId] = target;
    });
    if (changed) {
      widget.onSizeChanged(resize.itemId, target);
      HapticFeedback.lightImpact();
    }
  }

  /// 手势被系统取消（来电 / 通知下拉 / 竞技场被抢）：**回滚**，不提交尺寸。
  void _cancelResize() {
    if (_resize == null) return;
    setState(() => _resize = null);
  }

  void _syncEdgeScroll() {
    final drag = _drag;
    if (drag == null) {
      _edgeScroller.stop();
      return;
    }
    _edgeScroller.update(
      position: _scrollPos,
      viewport: _viewportBox(),
      pointer: drag.pointer,
    );
  }

  RenderBox? _viewportBox() {
    final scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    final box = scrollable?.context.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(
          0.0,
          constraints.maxWidth - widget.padding.horizontal,
        );
        final colWidth = math.max(
          1.0,
          (available - (kGridColumns - 1) * widget.spacing) / kGridColumns,
        );
        _colWidth = colWidth;
        final layout = GridLayout(
          metrics: GridCardMetrics(
            colWidth: colWidth,
            unitHeight: widget.unitHeight,
            gap: widget.spacing,
          ),
          padding: widget.padding,
        );
        final display = _displayItems();
        final reserved = _reservedSlot();
        // 先把占位块占住，其余卡片绕着它排 —— 悬浮卡片正下方永远是空的。
        final placements = reserved == null
            ? layout.pack(display)
            : layout.packReserved(display, reserved);
        _placements = placements;
        final drag = _drag;
        final resize = _resize;

        // 占位框也计入高度，否则拖到最下面会画不下。
        var height = layout.heightOf(placements);
        if (reserved != null) {
          final reservedRect = reserved.rectIn(
            colWidth,
            widget.unitHeight,
            widget.spacing,
            widget.padding,
          );
          height = math.max(height, reservedRect.bottom + widget.padding.bottom);
        }
        final reservedRect = reserved?.rectIn(
          colWidth,
          widget.unitHeight,
          widget.spacing,
          widget.padding,
        );

        // 卡片层：普通卡片 + 缩放中的本体 + 被拖动的悬浮卡。
        final layers = buildGridCardLayers(
          stackKey: _stackKey,
          layout: layout,
          placements: placements,
          items: widget.items,
          drag: drag,
          resize: resize,
          lastSizes: _lastSizes,
          editing: widget.editing,
          selectedId: widget.selectedId,
          colWidth: colWidth,
          spacing: widget.spacing,
          unitHeight: widget.unitHeight,
          sizeAnim: _sizeAnim,
          moveAnim: _moveAnim,
          onSelected: widget.onSelected,
          onResizeStart: _startResize,
          onResizeUpdate: _updateResize,
          onResizeEnd: _endResize,
          onResizeCancel: _cancelResize,
        );
        _lastSizes = layers.nextSizes;

        // 占位背景：拖动时 = 悬浮卡片的落点；缩放时 = 最近档位的大小，靠它把邻居推开。
        final showSlot =
            reservedRect != null && gridSlotVisible(drag: drag, resize: resize);

        return GestureDetector(
          // 空白处点击：退出整理；卡片自己会吸收点击，不会误触。
          onTap: widget.editing ? () => widget.onEditingChanged(false) : null,
          behavior: HitTestBehavior.opaque,
          // 长按识别器常驻：长按卡片入口、整理态里按住再拖都走它。
          onLongPressStart: _onLongPressStart,
          onLongPressMoveUpdate: _onLongPressMove,
          onLongPressEnd: _onLongPressEnd,
          onLongPressCancel: _onLongPressCancel,
          child: AnimatedSize(
            duration: _sizeAnim,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            child: SizedBox(
              key: _stackKey,
              width: double.infinity,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 占位 / 目标框永远压在最下层：主角是跟着手指走的卡片本体。
                  if (showSlot)
                    Positioned.fromRect(
                      key: const ValueKey<String>('fgrid-slot'),
                      rect: reservedRect,
                      child: IgnorePointer(
                        child: GridSlotPlaceholder(dashed: resize != null),
                      ),
                    ),
                  ...layers.cards,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
