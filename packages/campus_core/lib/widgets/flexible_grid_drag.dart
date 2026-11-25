import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'flexible_grid.dart';

/// 一次排版结果：卡片 + 在基础网格里的起始行列 + 像素矩形（含内边距）。
class GridPlacement {
  const GridPlacement({
    required this.item,
    required this.row,
    required this.col,
    required this.rect,
  });

  final FlexibleGridItem item;
  final int row;
  final int col;
  final Rect rect;
}

/// 拖动 / 缩放时被「占住」的格位：悬浮卡片下方要腾出的那块空位。
class GridReservation {
  const GridReservation({required this.row, required this.col, required this.size});

  final int row;
  final int col;
  final GridCardSize size;

  Rect rectIn(double colWidth, double unitHeight, double gap, EdgeInsets pad) =>
      Rect.fromLTWH(
        pad.left + col * (colWidth + gap),
        pad.top + row * (unitHeight + gap),
        size.columns * colWidth + (size.columns - 1) * gap,
        size.rows * unitHeight + (size.rows - 1) * gap,
      );
}

/// 拖动状态：卡片悬在手指下，落点在它正下方留一块空位。
class GridDragState {
  GridDragState({
    required this.itemId,
    required this.item,
    required this.size,
    required this.sizePx,
    required this.grab,
    required this.pointer,
    required this.origin,
    required this.originRow,
    required this.originCol,
  }) : startPointer = pointer;

  final String itemId;

  /// 起拖时的卡片（含尺寸与顺序位置）。
  final FlexibleGridItem item;

  final GridCardSize size;
  final Size sizePx;

  /// 手指相对卡片左上角的偏移（宫格本地坐标）：跟手时保持起手点不变。
  final Offset grab;

  /// 起拖时卡片在网格里的矩形 / 起手格位：还没拖开时占住这里，布局保持原样。
  final Rect origin;
  final int originRow;
  final int originCol;

  /// 起拖时的指针位置：用来判断「拖出去多远才算真的挪开」。
  final Offset startPointer;

  Offset pointer;

  /// 已经拖开（超过阈值）才把占位挪到落点，之前布局不动。
  bool movedAway = false;
}

/// 缩放状态：手柄跟手，尺寸连续变化，松手吸附到最近档位。
class GridResizeState {
  GridResizeState({
    required this.itemId,
    required this.start,
    required this.startPx,
    required this.startPointer,
    required this.originRow,
    required this.originCol,
  })  : currentPx = startPx,
        snapped = start,
        reserve = start;

  final String itemId;

  /// 起手档位与起手像素尺寸（连续缩放以它为基准）。
  final GridCardSize start;
  final Size startPx;

  /// 起手格位：缩放时占住这里（本体不动）。
  final int originRow;
  final int originCol;

  final Offset startPointer;

  /// 跟手的连续像素尺寸（只用来算档位，不直接画出）。
  Size currentPx;

  /// 最接近的设计档位：虚线背景按它画、松手提交它。
  GridCardSize snapped;

  /// 排斥用的尺寸：缩小时 = [snapped]，放大时 = 能装下当前尺寸的档位。
  GridCardSize reserve;

  /// 是否已经拖过死区（防手抖）。
  bool started = false;

  /// 尺寸标签（松手后会落到的档位）。
  String get label => snapped.label;
}

/// 网格排版：6 列 2D 首次适配装箱 + 占位格换算（拖拽 / 缩放的手势换算共用）。
class GridLayout {
  const GridLayout({required this.metrics, required this.padding});

  final GridCardMetrics metrics;
  final EdgeInsets padding;

  /// 某一格位的像素矩形（含内边距）。
  Rect rectFor(int row, int col, GridCardSize size) => Rect.fromLTWH(
        padding.left + col * (metrics.colWidth + metrics.gap),
        padding.top + row * (metrics.unitHeight + metrics.gap),
        size.columns * metrics.colWidth + (size.columns - 1) * metrics.gap,
        size.rows * metrics.unitHeight + (size.rows - 1) * metrics.gap,
      );

  /// 2D 首次适配：按传入顺序逐张找最靠前的空位，同样输入永远同样排版。
  List<GridPlacement> pack(List<FlexibleGridItem> items) {
    final occupied = <int, List<bool>>{};
    final out = <GridPlacement>[];
    for (final item in items) {
      final size = item.size;
      var placed = false;
      for (var row = 0; !placed; row++) {
        for (var col = 0; col + size.columns <= kGridColumns; col++) {
          var free = true;
          for (var r = row; r < row + size.rows && free; r++) {
            final line = occupied[r];
            if (line == null) continue;
            for (var c = col; c < col + size.columns; c++) {
              if (line[c]) {
                free = false;
                break;
              }
            }
          }
          if (!free) continue;
          for (var r = row; r < row + size.rows; r++) {
            final line = occupied.putIfAbsent(
              r,
              () => List<bool>.filled(kGridColumns, false),
            );
            for (var c = col; c < col + size.columns; c++) {
              line[c] = true;
            }
          }
          out.add(
            GridPlacement(
              item: item,
              row: row,
              col: col,
              rect: rectFor(row, col, size),
            ),
          );
          placed = true;
          break;
        }
      }
    }
    return out;
  }

  /// 先占住 [reserved] 再排其余卡片，于是悬浮卡片正下方始终是空的。
  List<GridPlacement> packReserved(
    List<FlexibleGridItem> items,
    GridReservation reserved,
  ) {
    final occupied = <int, List<bool>>{};

    void mark(int row, int col, GridCardSize size) {
      // 夹住边界：占位块可能贴着右边缘，越界写数组会抛 RangeError。
      final lastCol = math.min(kGridColumns, col + size.columns);
      final firstCol = math.max(0, col);
      for (var r = math.max(0, row); r < row + size.rows; r++) {
        final line = occupied.putIfAbsent(
          r,
          () => List<bool>.filled(kGridColumns, false),
        );
        for (var c = firstCol; c < lastCol; c++) {
          line[c] = true;
        }
      }
    }

    bool isFree(int row, int col, GridCardSize size) {
      for (var r = row; r < row + size.rows; r++) {
        final line = occupied[r];
        if (line == null) continue;
        for (var c = col; c < col + size.columns; c++) {
          if (line[c]) return false;
        }
      }
      return true;
    }

    mark(reserved.row, reserved.col, reserved.size);

    final out = <GridPlacement>[];
    for (final item in items) {
      final size = item.size;
      var placed = false;
      for (var row = 0; !placed; row++) {
        for (var col = 0; col + size.columns <= kGridColumns; col++) {
          if (!isFree(row, col, size)) continue;
          mark(row, col, size);
          out.add(
            GridPlacement(
              item: item,
              row: row,
              col: col,
              rect: rectFor(row, col, size),
            ),
          );
          placed = true;
          break;
        }
      }
    }
    return out;
  }

  /// 排版区总高：最低卡片下沿 + 底部内边距。
  double heightOf(List<GridPlacement> placements) {
    var bottom = padding.top;
    for (final p in placements) {
      bottom = math.max(bottom, p.rect.bottom);
    }
    return placements.isEmpty ? 0 : bottom + padding.bottom;
  }

  /// 指针落在「除被拖卡片以外」的哪两张之间（阅读顺序：先按行，再按左右半边）。
  int dropIndexFor(Offset local, List<FlexibleGridItem> others) {
    final layout = pack(others);
    for (var i = 0; i < layout.length; i++) {
      final rect = layout[i].rect;
      if (local.dy < rect.top) return i; // 在它上面 → 插到它前面
      if (local.dy <= rect.bottom) {
        // 同一行：左半边插前面，右半边继续往后看。
        if (local.dx < rect.center.dx) return i;
        continue;
      }
      // 在它下面 → 继续往后。
    }
    return layout.length;
  }

  /// 把被拖卡片插到指针处的下标，重排一次，取它落到的格子。
  GridReservation slotForDrop(
    GridDragState drag,
    Offset drop,
    List<FlexibleGridItem> baseItems,
  ) {
    final others = [
      for (final item in baseItems)
        if (item.id != drag.itemId) item,
    ];
    final index = dropIndexFor(drop, others).clamp(0, others.length);
    final sequence = <FlexibleGridItem>[...others]
      ..insert(index, drag.item);
    final layout = pack(sequence);
    for (final placement in layout) {
      if (placement.item.id == drag.itemId) {
        return GridReservation(
          row: placement.row,
          col: placement.col,
          size: drag.size,
        );
      }
    }
    return GridReservation(
      row: drag.originRow,
      col: drag.originCol,
      size: drag.size,
    );
  }
}

/// 两个 id 顺序是否完全一致。
bool gridSameOrder(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 刚落位、还在等 store 回写的新顺序 / 新尺寸（不等就会先弹回旧值再跳到新值）。
class GridPendingChanges {
  /// 尚未回写的新顺序。
  List<String>? order;

  /// 尚未回写的新尺寸。
  final Map<String, GridCardSize> sizes = <String, GridCardSize>{};

  /// 调用方数据 + 尚未回写的本地覆盖。
  List<FlexibleGridItem> applyTo(List<FlexibleGridItem> source) {
    var items = List<FlexibleGridItem>.of(source);
    final pending = order;
    if (pending != null) {
      final byId = {for (final item in items) item.id: item};
      if (pending.length == items.length && pending.every(byId.containsKey)) {
        items = [for (final id in pending) byId[id]!];
      }
    }
    if (sizes.isNotEmpty) {
      items = [
        for (final item in items)
          sizes[item.id] == null ? item : item.withSize(sizes[item.id]!),
      ];
    }
    return items;
  }

  /// store 回写后清掉已生效的覆盖。
  void settle(List<FlexibleGridItem> items) {
    final nowOrder = [for (final item in items) item.id];
    final pending = order;
    if (pending != null && gridSameOrder(nowOrder, pending)) order = null;
    sizes.removeWhere((id, size) {
      for (final item in items) {
        if (item.id == id) return item.size == size;
      }
      return true;
    });
  }
}
