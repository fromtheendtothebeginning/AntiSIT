import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 基础网格列数：卡片按 6 列等分，最宽档位占 3 列（半屏）。
const int kGridColumns = 6;

/// 卡片在 6 列基础网格上的占位：行数 × 列数（`2x3` = 2 行 × 3 列），档位目录见 [presets]。
@immutable
class GridCardSize {
  const GridCardSize(this.rows, this.columns)
    : assert(rows >= 1 && rows <= maxRows),
      assert(columns >= 1 && columns <= maxColumns);

  /// 高度最多几行（网格总共就这么多行）。
  static const int maxRows = 2;

  /// 宽度最多几列（网格 6 列，最宽档位是 3 列 = 半屏）。
  static const int maxColumns = 3;

  /// 高度占几行（1~[maxRows]）。
  final int rows;

  /// 宽度占几列（1~[maxColumns]）。
  final int columns;

  /// 1 行 1 列：只放图标的小方格。
  static const single = GridCardSize(1, 1);

  /// 1 行 3 列：半屏宽的横条。
  static const wide = GridCardSize(1, 3);

  /// 2 行 1 列：窄竖条（图标在上、文字在下）。
  static const narrow = GridCardSize(2, 1);

  /// 2 行 3 列：默认尺寸（半屏宽 × 128dp）。
  static const standard = GridCardSize(2, 3);

  /// 2 行 2 列：竖卡。
  static const tall = GridCardSize(2, 2);

  /// 默认尺寸：新建卡片、恢复默认都用它。
  static const defaultSize = standard;

  /// 全部可选档位（尺寸条按这个顺序排）。
  static const List<GridCardSize> presets = <GridCardSize>[
    single,
    wide,
    narrow,
    standard,
    tall,
  ];

  /// 按「占几格」从小到大排：连续缩放时按这个顺序一档一档吸附。
  static const byArea = <GridCardSize>[single, narrow, wide, tall, standard];

  /// 这一档在尺寸条 / 提示里的短名。
  String get specLabel => switch (key) {
        '1x1' => '小方格',
        '1x3' => '横条',
        '2x1' => '竖条',
        '2x2' => '竖卡',
        '2x3' => '默认',
        _ => label,
      };

  /// 内容排版取向：页面按它决定「只有图标 / 图标在左 / 图标在上 / 完整卡」。
  GridCardKind get kind => switch (key) {
        '1x1' => GridCardKind.iconOnly,
        '1x3' => GridCardKind.row,
        '2x1' => GridCardKind.stack,
        _ => GridCardKind.full,
      };

  /// 尺寸条上那个小预览的宽高（按行 × 列比例，封顶 22×16）。
  ({double w, double h}) get previewBox => (
        w: math.max(9, math.min(22, columns * 8)).toDouble(),
        h: math.max(8, math.min(16, rows * 7)).toDouble(),
      );

  /// 显示用标签（`2×3`，行 × 列）。
  String get label => '$rows×$columns';

  /// 落盘用的稳定 key（`2x3`，行 × 列）：ASCII，别跟着显示文案改。
  String get key => '${rows}x$columns';

  /// 解析落盘值；认不出来就回落到 [fallback]。
  static GridCardSize parse(Object? raw, {GridCardSize fallback = defaultSize}) {
    if (raw is! String) return fallback;
    final t = raw.trim().toLowerCase();
    for (final preset in presets) {
      if (preset.key == t) return preset;
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      other is GridCardSize && other.columns == columns && other.rows == rows;

  @override
  int get hashCode => Object.hash(columns, rows);

  @override
  String toString() => key;
}

/// 一种卡片尺寸的排版取向：页面据此决定内容怎么排。
enum GridCardKind {
  /// 只放一个图标（最小格，放不下名字）。
  iconOnly,

  /// 横向：图标在左、文字在右（1 行多列的横条）。
  row,

  /// 纵向：图标在上、文字在下，而且窄（多行 1 列的竖条）。
  stack,

  /// 完整卡：图标 / 标题 / 副标题都在（2x2、2x3）。
  full,
}

/// 网格几何换算：档位与像素尺寸互转（排版、缩放吸附、卡面排版共用）。
class GridCardMetrics {
  const GridCardMetrics({
    required this.colWidth,
    required this.unitHeight,
    required this.gap,
  });

  final double colWidth;
  final double unitHeight;
  final double gap;

  /// 某一档的像素尺寸（宽 × 高）。
  Size pxOf(GridCardSize size) => Size(
        size.columns * colWidth + (size.columns - 1) * gap,
        size.rows * unitHeight + (size.rows - 1) * gap,
      );

  /// 连续尺寸 → 最接近的设计档位（宽高各自按列 / 行步长归一后比距离）。
  GridCardSize nearestPreset(Size px) {
    final colStride = math.max(1.0, colWidth + gap);
    final rowStride = math.max(1.0, unitHeight + gap);
    var best = GridCardSize.presets.first;
    var bestDistance = double.infinity;
    for (final preset in GridCardSize.byArea) {
      final w = preset.columns * colWidth + (preset.columns - 1) * gap;
      final h = preset.rows * unitHeight + (preset.rows - 1) * gap;
      final dx = (px.width - w) / colStride;
      final dy = (px.height - h) / rowStride;
      final d = dx * dx + dy * dy;
      if (d < bestDistance) {
        best = preset;
        bestDistance = d;
      }
    }
    return best;
  }

  /// 缩放时的「排斥用尺寸」：缩小时取最近档位，放大时取能装下当前尺寸的最小档位。
  GridCardSize reserveFor(Size px, GridCardSize start) {
    final nearest = nearestPreset(px);
    final nearestPx = pxOf(nearest);
    final overflow =
        px.width > nearestPx.width + 0.5 || px.height > nearestPx.height + 0.5;
    if (!overflow) return nearest;

    final candidates = [
      for (final preset in GridCardSize.byArea)
        if (pxOf(preset).width >= px.width - 0.5 &&
            pxOf(preset).height >= px.height - 0.5)
          preset,
    ]..sort((a, b) => (a.rows * a.columns).compareTo(b.rows * b.columns));
    return candidates.isEmpty ? nearest : candidates.first;
  }

  /// 当前像素尺寸下该用哪一档的排版模式（能完整装进的最大一档）。
  GridCardSize layoutPresetFor(Size px) {
    var best = GridCardSize.presets.first;
    var bestArea = -1;
    for (final preset in GridCardSize.presets) {
      final box = pxOf(preset);
      if (box.width > px.width + 0.5 || box.height > px.height + 0.5) continue;
      final area = preset.rows * preset.columns;
      if (area > bestArea) {
        best = preset;
        bestArea = area;
      }
    }
    if (bestArea >= 0) return best;
    // 比最小档还小：用最小档排版，交给卡框裁切。
    return GridCardSize.single;
  }
}
