import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'flexible_grid.dart';
import 'glass_widgets.dart';
import 'theme_palette.dart';

/// 内容排版的基准尺寸：取卡片当前档位的完整尺寸，不跟着中间像素走（避免溢出）。
Size gridLayoutSizeFor({
  required FlexibleGridItem item,
  required Size fallback,
  required double colWidth,
  required double spacing,
  required double unitHeight,
}) {
  if (fallback.width > 0 && fallback.height > 0) return fallback;
  final size = item.size;
  return Size(
    size.columns * colWidth + (size.columns - 1) * spacing,
    size.rows * unitHeight + (size.rows - 1) * spacing,
  );
}

/// 把卡片内容按某一档的完整尺寸排好，再交给会变形的卡框裁切。
/// [anchorTopLeft] = true 时内容贴左上角（缩放跟手时图文位置不动，只有卡框边界在动）。
Widget gridCardFrame({
  required Size layoutSize,
  required Widget child,
  bool anchorTopLeft = false,
}) =>
    ClipRRect(
      borderRadius: BorderRadius.circular(cardRadius),
      clipBehavior: Clip.hardEdge,
      child: OverflowBox(
        alignment: anchorTopLeft ? Alignment.topLeft : Alignment.center,
        minWidth: layoutSize.width,
        maxWidth: layoutSize.width,
        minHeight: layoutSize.height,
        maxHeight: layoutSize.height,
        child: child,
      ),
    );

/// 缩放时卡片本体的位置与尺寸：左上角钉在起手格位，宽高跟着手指连续变。
Rect? gridResizeBodyRect(GridLayout layout, GridResizeState resize) {
  final origin = layout.rectFor(
    resize.originRow,
    resize.originCol,
    resize.start,
  );
  final px = resize.started ? resize.currentPx : resize.startPx;
  return Rect.fromLTWH(origin.left, origin.top, px.width, px.height);
}

/// 缩放中的卡片还够不够宽，能容下右上角的尺寸徽标（约 46×22）。
bool gridResizeBadgeFits(GridResizeState? resize) {
  if (resize == null) return false;
  final px = resize.started ? resize.currentPx : resize.startPx;
  return px.width >= 110 && px.height >= 50;
}

/// 占位背景现在要不要显示：拖动中拖开之后显示，缩放中离开死区后一直显示。
bool gridSlotVisible({GridDragState? drag, GridResizeState? resize}) {
  if (resize != null) return resize.started;
  return drag != null && drag.movedAway;
}

/// 拖动中的卡片矩形（宫格本地坐标）。
Rect? gridDraggedRect(GlobalKey stackKey, GridDragState? drag) {
  if (drag == null) return null;
  final box = stackKey.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  final local = box.globalToLocal(drag.pointer);
  return (local - drag.grab) & drag.sizePx;
}

/// 一张卡片的完整外观：内容 + 选中描边 + 右下角缩放弧线 + 尺寸徽标。
class GridCardFace extends StatelessWidget {
  const GridCardFace({
    super.key,
    required this.item,
    required this.editing,
    required this.selectedId,
    this.isDragged = false,
    this.isResizing = false,
    this.layoutAs,
    this.resizeLabel,
    this.badgeFits = false,
    this.onSelected,
    this.onResizeStart,
    this.onResizeUpdate,
    this.onResizeEnd,
  });

  final FlexibleGridItem item;
  final bool editing;
  final String? selectedId;
  final bool isDragged;
  final bool isResizing;

  /// 缩放中按这一档排版（null = 按卡片自己的档位）。
  final GridCardSize? layoutAs;

  /// 尺寸徽标上的文案（松手后会落到的档位）。
  final String? resizeLabel;

  /// 缩放中的卡片够不够宽显示尺寸徽标。
  final bool badgeFits;

  final ValueChanged<String>? onSelected;
  final ValueChanged<Offset>? onResizeStart;
  final ValueChanged<Offset>? onResizeUpdate;
  final VoidCallback? onResizeEnd;

  @override
  Widget build(BuildContext context) {
    // 缩放过程中按「最近能装下的那一档」排版：图标大小、标题行数、留白都跟着切换。
    Widget content = item.builder(
      context,
      layoutAs ?? item.size,
      editing,
    );

    // 抬起中的卡片垫一层实底：否则半透明玻璃面压在虚线填充上会被染色、比邻居暗一档。
    final liftedBacking = Color.alphaBlend(SemColors.card, SemColors.bg);
    if (isDragged) {
      content = IgnorePointer(
        child: Transform.scale(
          scale: 1.04,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: liftedBacking,
              borderRadius: BorderRadius.circular(cardRadius),
              boxShadow: [
                BoxShadow(
                  color: SemColors.shadow,
                  blurRadius: 28,
                  spreadRadius: 2,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: SemColors.accent.withValues(alpha: 0.28),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: content,
          ),
        ),
      );
    } else if (isResizing) {
      // 缩放中：卡片抬起一点点，这段手势只改尺寸、绝不换位置。
      content = IgnorePointer(
        child: Transform.scale(
          scale: 1.03,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: liftedBacking,
              borderRadius: BorderRadius.circular(cardRadius),
              boxShadow: [
                BoxShadow(
                  color: SemColors.shadow,
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: SemColors.accent.withValues(alpha: 0.24),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: content,
          ),
        ),
      );
    } else if (editing) {
      // 整理态里卡片本体只响应点击（选中），拖动统一交给外层长按识别器。
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelected?.call(item.id),
        child: content,
      );
    }

    final selected = editing && selectedId == item.id;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: content),
        if (selected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(cardRadius),
                  border: Border.all(
                    color: SemColors.accent.withValues(alpha: 0.8),
                    width: 1.6,
                  ),
                ),
              ),
            ),
          ),
        // 只给选中的卡片显示缩放弧线；调用方还没选中时退化成每张都显示。
        if (editing && !isDragged && (selectedId == null || selected))
          Positioned(right: 0, bottom: 0, child: _resizeHandle(context)),
        if (isResizing && badgeFits)
          // 尺寸徽标浮在右上角：内容贴左上角排，左下角常被标题 / 副标题占满。
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              child: Capsule(
                resizeLabel ?? item.size.label,
                color: SemColors.accent,
              ),
            ),
          ),
      ],
    );
  }

  /// 整理态的手势要先于列表滚动被识别：调小 touchSlop，pan 的接受阈值比列表更早。
  Widget _eagerGestures(BuildContext context, Widget child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          gestureSettings: const DeviceGestureSettings(touchSlop: 0.5),
        ),
        child: child,
      );

  Widget _resizeHandle(BuildContext context) {
    // 卡片越小角标越小：大角标会吃掉半个卡面，还跟「按住卡片拖动」抢手势。
    final tiny = item.size.kind == GridCardKind.iconOnly;
    final small = item.size.rows == 1;
    final hit = tiny ? 22.0 : (small ? 26.0 : 38.0);
    final paint = tiny ? 16.0 : (small ? 22.0 : 34.0);
    return _eagerGestures(
      context,
      GestureDetector(
        key: ValueKey<String>('fgrid-handle:${item.id}'),
        behavior: HitTestBehavior.opaque,
        // 从按下那一点算起：识别出手势之前滑过的那段也计入缩放。
        dragStartBehavior: DragStartBehavior.down,
        // 点角标 = 选中这张卡；不冒泡成「退出整理」。
        onTap: () => onSelected?.call(item.id),
        onPanStart: onResizeStart == null
            ? null
            : (d) => onResizeStart!(d.globalPosition),
        onPanUpdate: onResizeUpdate == null
            ? null
            : (d) => onResizeUpdate!(d.globalPosition),
        onPanEnd: onResizeEnd == null ? null : (_) => onResizeEnd!(),
        onPanCancel: onResizeEnd,
        child: SizedBox(
          width: hit,
          height: hit,
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: CustomPaint(
                size: Size(paint, paint),
                painter: CornerArcPainter(
                  color: SemColors.accent,
                  glow: SemColors.accent.withValues(alpha: 0.16),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 占位背景：拖动时 = 实心浅色块，缩放时 = 虚线框（表示松手后会变成的大小）。
class GridSlotPlaceholder extends StatelessWidget {
  const GridSlotPlaceholder({super.key, this.dashed = false});

  final bool dashed;

  @override
  Widget build(BuildContext context) {
    if (!dashed) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: SemColors.accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(cardRadius),
          border: Border.all(
            color: SemColors.accent.withValues(alpha: 0.4),
            width: 1.3,
          ),
        ),
      );
    }
    // 缩放目标框靠描边表达、不靠填充：半透明玻璃面被蓝填充压住会比邻居暗。
    return CustomPaint(
      painter: DashedBoxPainter(
        color: SemColors.accent.withValues(alpha: 1),
        fill: SemColors.accent.withValues(alpha: 0.06),
        glow: SemColors.accent.withValues(alpha: 0.45),
        radius: cardRadius,
        dash: 10,
        gap: 6,
        strokeWidth: 3,
      ),
    );
  }
}

/// 组装本次 build 的卡片层：普通卡片 + 缩放中的本体 + 被拖动的悬浮卡。
({List<Widget> cards, Map<String, Size> nextSizes}) buildGridCardLayers({
  required GlobalKey stackKey,
  required GridLayout layout,
  required List<GridPlacement> placements,
  required List<FlexibleGridItem> items,
  required GridDragState? drag,
  required GridResizeState? resize,
  required Map<String, Size> lastSizes,
  required bool editing,
  required String? selectedId,
  required double colWidth,
  required double spacing,
  required double unitHeight,
  required Duration sizeAnim,
  required Duration moveAnim,
  required ValueChanged<String>? onSelected,
  required void Function(FlexibleGridItem item, Offset global) onResizeStart,
  required ValueChanged<Offset> onResizeUpdate,
  required VoidCallback onResizeEnd,
}) {
  FlexibleGridItem? itemById(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  GridCardFace face(FlexibleGridItem item, {bool isDragged = false}) =>
      GridCardFace(
        item: item,
        editing: editing,
        selectedId: selectedId,
        isDragged: isDragged,
        onSelected: onSelected,
        onResizeStart: (g) => onResizeStart(item, g),
        onResizeUpdate: onResizeUpdate,
        onResizeEnd: onResizeEnd,
      );

  final cards = <Widget>[];
  final nextSizes = <String, Size>{
    for (final p in placements) p.item.id: p.rect.size,
  };

  for (final placement in placements) {
    final item = placement.item;
    // 卡框尺寸变了才播「跟随」动画（换档 / 邻居让位）。
    final previousSize = lastSizes[item.id];
    final sizeChanged =
        previousSize != null && previousSize != placement.rect.size;
    cards.add(
      SlotMotion(
        key: ValueKey<String>('fgrid:${item.id}'),
        target: placement.rect,
        // 换尺寸走慢一点、纯换位快一点；中途目标再变只换目标，动画带着当前速度继续。
        duration: sizeChanged ? sizeAnim : moveAnim,
        child: gridCardFrame(
          layoutSize: gridLayoutSizeFor(
            item: item,
            fallback: placement.rect.size,
            colWidth: colWidth,
            spacing: spacing,
            unitHeight: unitHeight,
          ),
          child: face(item),
        ),
      ),
    );
  }

  // 缩放中：本体跟着手指灵活缩放，虚线框画「最近的适配大小」，邻居按虚线框让位。
  if (resize != null) {
    final resizeItem = itemById(resize.itemId);
    final bodyRect = gridResizeBodyRect(layout, resize);
    if (resizeItem != null && bodyRect != null) {
      nextSizes[resizeItem.id] = bodyRect.size;
      cards.add(
        SlotMotion(
          key: ValueKey<String>('fgrid:${resizeItem.id}'),
          target: bodyRect,
          // 跟手：直接贴住目标，不播动画。
          snap: true,
          duration: sizeAnim,
          child: gridCardFrame(
            // 卡面铺满跟手框，内部再按 layoutAs 用对应档位排版。
            layoutSize: bodyRect.size,
            // 贴左上角：缩放时图标与文字的绝对位置不动，只有卡框边界在动。
            anchorTopLeft: true,
            child: GridCardFace(
              item: resizeItem,
              editing: editing,
              selectedId: selectedId,
              isResizing: true,
              resizeLabel: resize.label,
              badgeFits: gridResizeBadgeFits(resize),
              layoutAs: layout.metrics.layoutPresetFor(bodyRect.size),
              onSelected: onSelected,
              onResizeStart: (g) => onResizeStart(resizeItem, g),
              onResizeUpdate: onResizeUpdate,
              onResizeEnd: onResizeEnd,
            ),
          ),
        ),
      );
    }
  }

  // 被拖动的卡片不在 placements 里（悬在手指下、不参与流式排版），单独画在最上层。
  if (drag != null) {
    final dragItem = itemById(drag.itemId);
    final dragRect = gridDraggedRect(stackKey, drag);
    if (dragItem != null && dragRect != null) {
      nextSizes[dragItem.id] = dragRect.size;
      cards.add(
        SlotMotion(
          key: ValueKey<String>('fgrid:${dragItem.id}'),
          target: dragRect,
          // 跟手：直接贴住目标，不播动画。
          snap: true,
          duration: moveAnim,
          child: gridCardFrame(
            layoutSize: gridLayoutSizeFor(
              item: dragItem,
              fallback: dragRect.size,
              colWidth: colWidth,
              spacing: spacing,
              unitHeight: unitHeight,
            ),
            child: face(dragItem, isDragged: true),
          ),
        ),
      );
    }
  }

  return (cards: cards, nextSizes: nextSizes);
}

