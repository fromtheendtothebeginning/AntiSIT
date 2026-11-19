import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'glass_widgets.dart';
import 'theme_palette.dart';

/// 卡片在 6 列基础网格上的占位：**行数 × 列数**（`2x3` = 2 行 × 3 列）。
///
/// 四种设计尺寸：
/// * [single]  `1x1`：1 行 × 1 列——最小的一格（约 1/6 屏宽 × 59dp，接近小方块）；
/// * [wide]    `1x3`：1 行 × 3 列——半屏宽的横条；
/// * [standard]`2x3`：2 行 × 3 列——**原来的默认大小**（半屏宽 × 128dp）；
/// * [tall]    `2x2`：2 行 × 2 列——1/3 屏宽的竖卡。
///
/// 行高由 [FlexibleCardGrid.unitHeight] 决定（默认 59dp）：2 行 + 1 个间距 = 128dp，
/// 与旧宫格默认卡片高度一致；宽度按剩余宽度均分 6 列，3 列恰好是旧卡片的半屏宽。
@immutable
class GridCardSize {
  const GridCardSize(this.rows, this.columns)
    : assert(rows >= 1 && rows <= 2),
      assert(columns >= 1 && columns <= 3);

  /// 高度占几行（1~2）。
  final int rows;

  /// 宽度占几列（1~3）。
  final int columns;

  static const single = GridCardSize(1, 1);
  static const wide = GridCardSize(1, 3);
  static const standard = GridCardSize(2, 3);
  static const tall = GridCardSize(2, 2);

  /// 顶部尺寸按钮 / 手柄吸附到的四种设计尺寸（按「宽 × 高」的观感排）。
  static const presets = <GridCardSize>[single, wide, standard, tall];

  /// 按「占几格」从小到大排：左右滑动换尺寸时按这个顺序一档一档走
  /// （1×1 = 1 格 → 1×3 = 3 格 → 2×2 = 4 格 → 2×3 = 6 格）。
  static const byArea = <GridCardSize>[single, wide, tall, standard];

  /// 显示用标签（`2×3`，行×列）。
  String get label => '$rows×$columns';

  /// 落盘用的稳定 key（`2x3`，行×列）：ASCII，别跟着显示文案改。
  String get key => '${rows}x$columns';

  /// 解析落盘值；认不出来就回落到 [fallback]。
  static GridCardSize parse(Object? raw, {GridCardSize fallback = standard}) {
    if (raw is! String) return fallback;
    switch (raw.trim().toLowerCase()) {
      case '1x1':
        return single;
      case '1x3':
        return wide;
      case '2x3':
        return standard;
      case '2x2':
        return tall;
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

/// [FlexibleCardGrid] 里的一张卡片：id 用来认人 / 落盘，size 是当前占位，
/// builder 负责画卡片本身（页面据此做不同尺寸的排版）。
typedef FlexibleCardBuilder =
    Widget Function(BuildContext context, GridCardSize size, bool editing);

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

/// ColorOS 风格的卡片尺寸切换条：选中卡片后，顶部一排四档尺寸的缩略预览按钮。
///
/// 按钮只画「卡片比例的小预览」不加长文字，点一下就把选中卡片换成那一档；
/// 当前尺寸用强调色高亮，左边同时写出 `卡片大小 · 2×3`。
/// 选中哪张卡片由页面维护（[FlexibleCardGrid.selectedId]），这里只负责显示与点击。
class CardSizeBar extends StatelessWidget {
  const CardSizeBar({super.key, required this.size, required this.onChanged});

  /// 当前选中卡片的尺寸；null = 还没选中卡片（整排按钮置灰）。
  final GridCardSize? size;

  /// 点了某一档尺寸（调用方负责写到选中卡片上）。
  final ValueChanged<GridCardSize> onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = size != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 点条本身的空白不要冒泡成页面级的「退出整理」
      onTap: () {},
      child: Container(
        key: const ValueKey<String>('card-size-bar'),
        padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
        decoration: BoxDecoration(
          color: SemColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SemColors.accent.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(Icons.tune_rounded, size: 16, color: SemColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                enabled ? '卡片大小 · ${size!.label}' : '点选一张卡片调整大小',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: enabled
                      ? SemColors.textSecondary
                      : SemColors.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 6),
            for (final preset in GridCardSize.presets) ...[
              _SizeOption(
                preset: preset,
                selected: size == preset,
                enabled: enabled,
                onTap: () => onChanged(preset),
              ),
              if (preset != GridCardSize.presets.last) const SizedBox(width: 5),
            ],
          ],
        ),
      ),
    );
  }
}

class _SizeOption extends StatelessWidget {
  const _SizeOption({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final GridCardSize preset;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? SemColors.accent : SemColors.textMuted;
    final single = preset == GridCardSize.single;
    final wide = preset == GridCardSize.wide;
    final tall = preset == GridCardSize.tall;
    final w = single ? 10.0 : (wide ? 22.0 : (tall ? 14.0 : 22.0));
    final h = single ? 10.0 : (wide ? 8.0 : (tall ? 16.0 : 15.0));
    final label = single
        ? '1×1 小方格'
        : wide
        ? '1×3 横条'
        : tall
        ? '2×2 竖卡'
        : '2×3 默认';
    return Semantics(
      button: true,
      selected: selected,
      label: '卡片大小 $label',
      child: Tooltip(
        message: label,
        child: GestureDetector(
          key: ValueKey<String>('card-size-option:${preset.key}'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 40,
            height: 32,
            decoration: BoxDecoration(
              color: selected
                  ? SemColors.accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? SemColors.accent : SemColors.border,
                width: selected ? 1.2 : 1,
              ),
            ),
            child: Opacity(
              opacity: enabled ? 1 : 0.4,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    color: selected
                        ? SemColors.accent.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: fg, width: 1.4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 可整理（长按拖动换位 / 顶部尺寸按钮 / 拖右下角弧线 / 左右滑改大小）的柔性宫格。
///
/// 排版：6 列基础网格 + 2D 首次适配装箱，卡片按传入顺序从左到右、从上到下找空位。
/// 尺寸只有 [GridCardSize.presets] 四种设计档位（1x1 / 1x3 / 2x3 / 2x2，行×列）。
///
/// 手势：
/// * 普通状态：长按卡片 → 震动并立即进入整理状态、选中并跟手抬起。
/// * 整理状态：**方向锁**——第一段位移以竖向为主 = 换位置；以横向为主 =
///   **左右滑动直接改尺寸**（往右变大、往左变小，一档一档走）。
///   另外还能拖选中卡片右下角的弧线细调；点卡片选中它；点别处退出整理。
/// * 拖动到列表上下边缘时自动滚动，长列表也能把卡片拖到屏幕外。///
/// 状态全部由调用方持有（[editing] / [onEditingChanged] / [onOrderChanged] /
/// [onSizeChanged]），落盘与启停规则都留在各页自己的 store 里；本组件只做排版与手势。
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

  /// 拖拽落位后的新顺序（按卡片 id）。仅在顺序真的变了时回调。
  final ValueChanged<List<String>> onOrderChanged;

  /// 缩放落位后的新尺寸。仅在尺寸真的变了时回调。
  final void Function(String id, GridCardSize size) onSizeChanged;

  /// 当前选中的卡片：顶部尺寸切换条作用于它，也只有它显示右下角缩放弧线。
  /// 传 null 时（调用方还没选）退化成每张卡都显示弧线，保证不会没法操作。
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

/// 一次拖动的方向锁：决定这一段手势是换位置还是换尺寸。
enum _DragAxisKind { horizontal, vertical }

class _FlexibleCardGridState extends State<FlexibleCardGrid>
    with SingleTickerProviderStateMixin {
  static const int _columns = 6;
  static const double _maxEdgeScrollSpeed = 900; // px/s

  /// 换尺寸的过渡：比换位慢、走「先快后极慢」的减速曲线，
  /// 卡片像被轻轻推着长开 / 收回（ColorOS 改小组件尺寸的那种手感）。
  /// 480ms 是「明显能看清过程」的长度，再短就显得像直接跳过去。
  static const Duration _sizeAnim = Duration(milliseconds: 520);
  static const Curve _sizeCurve = Cubic(0.12, 0.68, 0.06, 1.0);

  /// 只是换位置的过渡（邻居让位）：短一点，避免整页跟着「飘」。
  static const Duration _moveAnim = Duration(milliseconds: 300);
  static const Curve _moveCurve = Curves.easeOutCubic;

  /// 拖出去多远才算「真的挪开」：低于这个距离时卡片还算在原位，
  /// 邻居不让位、原格子的占位符也一直亮着。
  static const double _moveAwayThreshold = 14;

  /// 弧线手柄每跨一档要拖的像素：判定范围调大 = 这个数小，轻轻一拖就换档。
  static const double _handleStep = 32;

  /// 左右滑每跨一档要横移的像素。判定范围比「滑过一整个列宽」大得多
  /// （列宽约 55~90dp），轻轻一划就能换档。
  static const double _swipeStep = 40;

  /// 左右滑的死区系数：位移不到 [_swipeStep] × 这个比例时完全不换档，
  /// 免得手一动就跳档。
  static const double _swipeDeadZone = 0.6;

  /// 整个排版区的 RenderBox：把手指的全局坐标换算成宫格坐标。
  final GlobalKey _stackKey = GlobalKey();

  /// 最近的竖向滚动容器（工具栏 / 拓展页都在可滚动页面里，拖到边缘要自己滚）。
  ScrollPosition? _scrollPos;

  /// 拖动中：卡片在手指下，松手才落位 / 才提交尺寸。
  _DragState? _drag;

  /// 缩放中：手柄跟手，尺寸吸附到最近的设计档位。
  _ResizeState? _resize;

  /// 刚落位、还在等 store 回写的新顺序 / 新尺寸。
  /// 不等它就会「先弹回旧顺序 → 下一帧再跳成新顺序」，看着闪一下。
  List<String>? _pendingOrder;
  final Map<String, GridCardSize> _pendingSizes = <String, GridCardSize>{};

  /// 上一次 build 的几何：手势回调里要用它算「按在哪个卡片上」。
  double _colWidth = 0;
  List<_Placement> _placements = const [];

  /// 上一帧每张卡的像素尺寸：判断这次是「换位置」还是「卡框要长 / 要收」。
  Map<String, Size> _lastSizes = const {};

  /// 自动滚动 ticker（只在拖动到边缘时跑）。
  Ticker? _edgeTicker;
  Duration _lastTick = Duration.zero;
  double _edgeSpeed = 0;

  @override
  void initState() {
    super.initState();
    _edgeTicker = createTicker(_onEdgeTick);
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
      // 页面点了「完成」：拖动 / 缩放一起收掉
      _stopEdgeScroll();
      _drag = null;
      _resize = null;
    }
    if (_drag != null && !ids.contains(_drag!.itemId)) _drag = null;
    if (_resize != null && !ids.contains(_resize!.itemId)) _resize = null;

    // store 已把新顺序 / 新尺寸写回来 → 本地覆盖可以撤了
    final nowOrder = [for (final item in widget.items) item.id];
    final pending = _pendingOrder;
    if (pending != null && _sameOrder(nowOrder, pending)) _pendingOrder = null;
    _pendingSizes.removeWhere((id, size) {
      final item = _itemById(id);
      return item == null || item.size == size;
    });
  }

  @override
  void dispose() {
    _edgeTicker?.dispose();
    super.dispose();
  }

  FlexibleGridItem? _itemById(String id) {
    for (final item in widget.items) {
      if (item.id == id) return item;
    }
    return null;
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 不拖动、不缩放时的基准顺序 / 尺寸：调用方数据 + 尚未回写的本地覆盖。
  List<FlexibleGridItem> _baseItems() {
    var items = List<FlexibleGridItem>.of(widget.items);
    final pending = _pendingOrder;
    if (pending != null) {
      final byId = {for (final item in items) item.id: item};
      if (pending.length == items.length && pending.every(byId.containsKey)) {
        items = [for (final id in pending) byId[id]!];
      }
    }
    if (_pendingSizes.isNotEmpty) {
      items = [
        for (final item in items)
          _pendingSizes[item.id] == null
              ? item
              : item.withSize(_pendingSizes[item.id]!),
      ];
    }
    return items;
  }

  /// 真正要画出来的顺序：基准顺序 → 缩放中的临时尺寸 → 拖动中的临时状态。
  ///
  /// * 竖向拖动但还没拖够距离：卡片留在原来的槽位（占位符留在原地）。
  /// * 竖向拖开了：按计算出来的插入点让位。
  /// * 横向拖动（改尺寸）：卡片留在原槽位，按**预览尺寸**重新排版，
  ///   邻居实时让位；松手才提交。
  List<FlexibleGridItem> _displayItems() {
    var items = _baseItems();
    final resize = _resize;
    if (resize != null) {
      final current = resize.current;
      items = [
        for (final item in items)
          item.id == resize.itemId ? item.withSize(current) : item,
      ];
    }
    final drag = _drag;
    if (drag != null) {
      final dragged = items.where((item) => item.id == drag.itemId).firstOrNull;
      if (dragged != null) {
        final horizontal = drag.axis == _DragAxisKind.horizontal;
        final shown = horizontal && drag.previewSize != null
            ? dragged.withSize(drag.previewSize!)
            : dragged;
        items = [
          for (final item in items)
            if (item.id != drag.itemId) item,
        ];
        final index =
            (drag.movedAway &&
                drag.axis == _DragAxisKind.vertical &&
                !horizontal)
            ? drag.insert
            : drag.originIndex;
        items.insert(index.clamp(0, items.length), shown);
      }
    }
    return items;
  }

  // ==================== 排版 ====================

  Rect _rectFor(int row, int col, GridCardSize size, double colWidth) {
    final gap = widget.spacing;
    return Rect.fromLTWH(
      widget.padding.left + col * (colWidth + gap),
      widget.padding.top + row * (widget.unitHeight + gap),
      size.columns * colWidth + (size.columns - 1) * gap,
      size.rows * widget.unitHeight + (size.rows - 1) * gap,
    );
  }

  /// 2D 首次适配：按传入顺序逐张找最靠前的空位（6 列，卡片宽 1~3 列、高 1~2 行）。
  /// 顺序稳定、不依赖碰运气：同样的输入永远得到同样的排版。
  List<_Placement> _pack(List<FlexibleGridItem> items, double colWidth) {
    final occupied = <int, List<bool>>{};
    final out = <_Placement>[];
    for (final item in items) {
      final size = item.size;
      var placed = false;
      for (var row = 0; !placed; row++) {
        for (var col = 0; col + size.columns <= _columns; col++) {
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
              () => List<bool>.filled(_columns, false),
            );
            for (var c = col; c < col + size.columns; c++) {
              line[c] = true;
            }
          }
          out.add(
            _Placement(
              item: item,
              row: row,
              col: col,
              rect: _rectFor(row, col, size, colWidth),
            ),
          );
          placed = true;
          break;
        }
      }
    }
    return out;
  }

  double _gridHeight(List<_Placement> placements) {
    var bottom = widget.padding.top;
    for (final p in placements) {
      bottom = math.max(bottom, p.rect.bottom);
    }
    return placements.isEmpty ? 0 : bottom + widget.padding.bottom;
  }

  Offset? _toLocal(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.globalToLocal(global);
  }

  _Placement? _hitTest(Offset local) {
    // 后画的在上面：从后往前找，拖动中的卡片盖住别人时也先命中它
    for (final p in _placements.reversed) {
      if (p.rect.contains(local)) return p;
    }
    return null;
  }

  // ==================== 长按 / 拖动 ====================

  void _onLongPressStart(LongPressStartDetails details) {
    if (_drag != null || _resize != null) return;
    final local = _toLocal(details.globalPosition);
    if (local == null) return;
    final hit = _hitTest(local);
    if (hit == null) return; // 长按在空白 / 卡片缝隙里：不进整理
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
    final baseItems = _baseItems();
    final originIndex = baseItems.indexWhere((e) => e.id == item.id);
    setState(() {
      _resize = null;
      _drag = _DragState(
        itemId: item.id,
        item: item,
        size: item.size,
        sizePx: rect.size,
        grab: local - rect.topLeft,
        pointer: global,
        origin: rect,
        originIndex: originIndex < 0 ? 0 : originIndex,
        insert: _insertIndexFor(local, item.id),
      );
    });
    _syncEdgeScroll();
  }

  void _startPanDrag(FlexibleGridItem item, Offset global) {
    if (_drag != null || _resize != null) return;
    final placement = _placements
        .where((p) => p.item.id == item.id)
        .firstOrNull;
    if (placement == null) return;
    _beginDrag(item, placement.rect, global);
  }

  /// 拖动的两种模式，按手指主导方向自动选（一次拖动只做一件事）：
  ///
  /// * **竖向为主**：换位置（按阅读顺序算插入点，和以前一样）。
  /// * **横向为主**：整理阶段左右滑动**优先改尺寸**，一档一档走
  ///   （往右变大、往左变小）。
  ///
  /// 方向锁在第一次越过 [_moveAwayThreshold] 时定下，中途不切换——
  /// 否则斜着拖会又挪位又换尺寸。阈值内什么都不做，
  /// 正好和「拖够距离才让位」共用同一段距离。
  void _updateDrag(Offset global) {
    final drag = _drag;
    if (drag == null) return;
    final local = _toLocal(global);
    if (local == null) return;
    final raw = global - drag.startPointer;
    final movedAway = raw.distance >= _moveAwayThreshold;

    if (drag.axis == null && movedAway) {
      drag.axis = raw.dx.abs() >= raw.dy.abs()
          ? _DragAxisKind.horizontal
          : _DragAxisKind.vertical;
      drag.movedAway = true;
      HapticFeedback.selectionClick();
    }
    if (drag.axis == null) {
      // 还没拖开：卡片留在原位、占位符不动，只记指针（长按后的轻微抖动不算数）
      setState(() => drag.pointer = global);
      return;
    }

    if (drag.axis == _DragAxisKind.horizontal) {
      _updateSwipeResize(drag, global, raw);
      return;
    }

    final insert = _insertIndexFor(local, drag.itemId);
    if (insert != drag.insert) HapticFeedback.selectionClick();
    setState(() {
      drag.pointer = global;
      drag.insert = insert;
      drag.movedAway = movedAway;
    });
    _syncEdgeScroll();
  }

  /// 整理阶段「左右滑 = 改尺寸」：以起手尺寸为基准，横移每过一档的 2/3
  /// （[_swipeDeadZone] 死区）就升 / 降一档。判定范围比「一整个列步长」宽，
  /// 轻轻一划就能换档；死区让手指刚动时不会立刻跳。
  ///
  /// 档位是连续的（[_swipeSteps] 按位移算），划得快也不会漏档。
  void _updateSwipeResize(_DragState drag, Offset global, Offset raw) {
    final order = GridCardSize.byArea;
    final startIndex = order.indexOf(drag.item.size);
    if (startIndex < 0) return;

    final steps = _swipeSteps(
      raw.dx,
    ).clamp(-startIndex, order.length - 1 - startIndex);
    final nextSize = order[startIndex + steps];
    if (steps == drag.steps && nextSize == drag.previewSize) {
      setState(() => drag.pointer = global);
      return;
    }
    if (nextSize != drag.previewSize) HapticFeedback.selectionClick();
    setState(() {
      drag.steps = steps;
      drag.previewSize = nextSize;
      drag.pointer = global;
    });
  }

  /// 横移 `dx` 对应「升几档」：正 = 往右变大。
  ///
  /// 用「死区 + 每档 [_swipeStep]」的分段：第一档只要滑过 0.6 个 [_swipeStep]，
  /// 之后每多滑一个 [_swipeStep] 再升一档，判定范围比一整列宽大得多。
  int _swipeSteps(double dx) {
    final a = dx.abs();
    final dead = _swipeStep * _swipeDeadZone;
    if (a < dead) return 0;
    final mag = ((a - dead) / _swipeStep).floor() + 1;
    return dx >= 0 ? mag : -mag;
  }

  void _endDrag() {
    final drag = _drag;
    if (drag == null) return;
    _stopEdgeScroll();

    // 横向拖动 = 改尺寸：松手只提交尺寸，不参与顺序。
    if (drag.axis == _DragAxisKind.horizontal) {
      final size = drag.previewSize;
      final changed = size != null && size != drag.item.size;
      setState(() {
        _drag = null;
        if (changed) _pendingSizes[drag.itemId] = size;
      });
      if (changed) {
        widget.onSizeChanged(drag.itemId, size);
        HapticFeedback.lightImpact();
      }
      return;
    }

    final ordered = _displayItems();
    final ids = [for (final item in ordered) item.id];
    final baseIds = [for (final item in _baseItems()) item.id];
    final changed = !_sameOrder(ids, baseIds);
    setState(() {
      _drag = null;
      if (changed) _pendingOrder = List<String>.of(ids);
    });
    if (changed) {
      widget.onOrderChanged(ids);
      HapticFeedback.lightImpact();
    }
  }

  void _cancelDrag() {
    if (_drag == null) return;
    _stopEdgeScroll();
    setState(() => _drag = null);
  }

  /// 指针落在「除被拖卡片以外」的哪两张之间：按阅读顺序，先看是否在这一行
  /// （落在卡片上下沿之间），同一行再按左右半边决定塞在它前面还是后面。
  /// 参照布局用**不含被拖卡片**的那份（稳定、不会因为卡片跟着让位而自己抖）。
  int _insertIndexFor(Offset local, String draggedId) {
    final others = [
      for (final item in _baseItems())
        if (item.id != draggedId) item,
    ];
    final layout = _pack(others, _colWidth);
    for (var i = 0; i < layout.length; i++) {
      final rect = layout[i].rect;
      if (local.dy < rect.top) return i; // 在它上面 → 插到它前面
      if (local.dy <= rect.bottom) {
        // 同一行：在左半边就插到它前面，在右半边就继续往后看
        if (local.dx < rect.center.dx) return i;
        continue;
      }
      // 在它下面 → 继续往后
    }
    return layout.length;
  }

  // ==================== 弧线缩放 ====================

  void _startResize(FlexibleGridItem item, Offset global) {
    if (_drag != null || _resize != null) return;
    final placement = _placements
        .where((p) => p.item.id == item.id)
        .firstOrNull;
    if (placement == null) return;
    widget.onSelected?.call(item.id);
    setState(() {
      _drag = null;
      _resize = _ResizeState(
        itemId: item.id,
        start: item.size,
        current: item.size,
        startPx: placement.rect.size,
        startPointer: global,
      );
    });
    HapticFeedback.selectionClick();
  }

  void _updateResize(Offset global) {
    final resize = _resize;
    if (resize == null) return;
    final delta = global - resize.startPointer;
    final next = _nearestPreset(resize.start, delta);
    if (next == resize.current) return;
    HapticFeedback.selectionClick();
    setState(() => resize.current = next);
  }

  void _endResize() {
    final resize = _resize;
    if (resize == null) return;
    final changed = resize.current != resize.start;
    setState(() {
      _resize = null;
      if (changed) _pendingSizes[resize.itemId] = resize.current;
    });
    if (changed) {
      widget.onSizeChanged(resize.itemId, resize.current);
      HapticFeedback.lightImpact();
    }
  }

  /// 手柄拖到的位移 → 该换到哪一档。
  ///
  /// 判定按**拖动方向**分档，每档只要拖够 [_handleStep]（32px）就换，
  /// 判定范围比「拖到另一档的像素宽度」大得多；拖得越远跨得越多。
  ///
  /// * **横向为主**：沿着「大小顺序」（[GridCardSize.byArea]）逐档走——
  ///   往右变大、往左变小。2×3 → 2×2 → 1×3 → 1×1 这样一路缩下去，
  ///   不会出现「拖了没反应」。
  /// * **竖向为主**：只改行数（2 行 ⇄ 1 行），列数不变。
  GridCardSize _nearestPreset(GridCardSize start, Offset delta) {
    final absX = delta.dx.abs();
    final absY = delta.dy.abs();
    final movedX = absX >= _handleStep;
    final movedY = absY >= _handleStep;
    // 只挪了一点点：保持原尺寸（防手抖）
    if (!movedX && !movedY) return start;

    final horizontalLead = movedX && (!movedY || absX >= absY);
    if (horizontalLead) {
      final order = GridCardSize.byArea;
      final startIndex = order.indexOf(start);
      if (startIndex < 0) return start;
      // 拖了「几档」：至少 1 档，拖得远就多跨几档
      final span = absX / _handleStep;
      final steps = math.max(1, span.floor());
      final target = (delta.dx >= 0 ? startIndex + steps : startIndex - steps)
          .clamp(0, order.length - 1);
      return order[target];
    }

    // 竖向：只改行数
    final span = absY / _handleStep;
    final steps = math.max(1, span.floor());
    final rows = (delta.dy >= 0 ? start.rows + steps : start.rows - steps)
        .clamp(1, 2);
    return _presetWithRows(rows, start.columns, delta) ?? start;
  }

  /// 行数固定时挑一个设计档位：优先列数最接近 [cols]，同距离按拖动方向选边。
  static GridCardSize? _presetWithRows(int rows, int cols, Offset delta) {
    final candidates = [
      for (final preset in GridCardSize.presets)
        if (preset.rows == rows) preset,
    ];
    if (candidates.isEmpty) return null;
    final target = cols.clamp(1, 3);
    for (final preset in candidates) {
      if (preset.columns == target) return preset;
    }
    candidates.sort((a, b) {
      final da = (a.columns - target).abs();
      final db = (b.columns - target).abs();
      if (da != db) return da.compareTo(db);
      return delta.dx >= 0
          ? b.columns.compareTo(a.columns)
          : a.columns.compareTo(b.columns);
    });
    return candidates.first;
  }

  // ==================== 拖动到边缘自动滚动 ====================

  void _syncEdgeScroll() {
    final drag = _drag;
    if (drag == null || drag.axis == _DragAxisKind.horizontal) {
      _stopEdgeScroll();
      return;
    }
    final viewport = _viewportBox();
    final pos = _scrollPos;
    if (viewport == null || pos == null || !pos.hasContentDimensions) {
      _stopEdgeScroll();
      return;
    }
    final topLeft = viewport.localToGlobal(Offset.zero);
    final top = topLeft.dy;
    final bottom = top + viewport.size.height;
    final edge = math.min(widget.autoScrollEdge, viewport.size.height / 3);
    final y = drag.pointer.dy;
    var speed = 0.0;
    if (y < top + edge) {
      speed = -_maxEdgeScrollSpeed * ((top + edge - y) / edge).clamp(0.0, 1.0);
    } else if (y > bottom - edge) {
      speed =
          _maxEdgeScrollSpeed * ((y - (bottom - edge)) / edge).clamp(0.0, 1.0);
    }
    _edgeSpeed = speed;
    if (speed == 0) {
      _stopEdgeScroll();
      return;
    }
    if (_edgeTicker?.isActive != true) {
      _lastTick = Duration.zero;
      _edgeTicker?.start();
    }
  }

  RenderBox? _viewportBox() {
    final scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    final box = scrollable?.context.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  void _stopEdgeScroll() {
    _edgeSpeed = 0;
    if (_edgeTicker?.isActive == true) _edgeTicker?.stop();
  }

  void _onEdgeTick(Duration elapsed) {
    final pos = _scrollPos;
    final drag = _drag;
    if (pos == null || drag == null || _edgeSpeed == 0) {
      _stopEdgeScroll();
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    if (dt <= 0 || !pos.hasContentDimensions || !pos.hasViewportDimension) {
      return;
    }
    final target = (pos.pixels + _edgeSpeed * dt).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    if ((target - pos.pixels).abs() < 0.5) return;
    pos.jumpTo(target);
    // 内容滚了：手指没动，但换算到宫格坐标系的位置变了——重新算落点并重画，
    // 否则占位框停在原处、拖起来的卡片会被内容带走。
    final local = _toLocal(drag.pointer);
    if (local == null) return;
    final insert = _insertIndexFor(local, drag.itemId);
    if (insert != drag.insert) HapticFeedback.selectionClick();
    setState(() => drag.insert = insert);
  }

  // ==================== 界面 ====================

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
          (available - (_columns - 1) * widget.spacing) / _columns,
        );
        _colWidth = colWidth;
        final display = _displayItems();
        final placements = _pack(display, colWidth);
        _placements = placements;
        final height = _gridHeight(placements);
        final drag = _drag;
        final resize = _resize;

        final cards = <Widget>[];
        final draggedId = drag?.itemId;
        final lifting = drag != null && drag.axis != _DragAxisKind.horizontal;
        final nextSizes = <String, Size>{
          for (final p in placements) p.item.id: p.rect.size,
        };
        // 被拖起来的卡片最后画，免得被后画的邻居盖住
        final ordered = [
          for (final p in placements)
            if (p.item.id != draggedId) p,
          if (draggedId != null)
            for (final p in placements)
              if (p.item.id == draggedId) p,
        ];

        for (final placement in ordered) {
          final item = placement.item;
          final isDragged = item.id == draggedId && lifting;
          final isResizing = item.id == resize?.itemId;
          final rect = isDragged
              ? _draggedRect(drag, placement) ?? placement.rect
              : placement.rect;
          // 卡框尺寸变了（换档）才播「跟随」动画：内容已经按目标尺寸排好，
          // 框自己补间长 / 收，看着就是卡片跟着手势长大或收起。
          final previousSize = _lastSizes[item.id];
          final sizeChanged = previousSize != null && previousSize != rect.size;
          cards.add(
            AnimatedPositioned(
              key: ValueKey<String>('fgrid:${item.id}'),
              // 拖动 / 缩放跟手时不补间（会拖出橡皮筋的感觉）；
              // 换尺寸走慢一点的减速曲线，邻居让位走短一点的过渡。
              duration: isDragged || isResizing
                  ? Duration.zero
                  : (sizeChanged ? _sizeAnim : _moveAnim),
              curve: sizeChanged ? _sizeCurve : _moveCurve,
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: _framed(
                rect: rect,
                child: _card(
                  context,
                  item: item,
                  isDragged: isDragged,
                  isResizing: isResizing,
                ),
              ),
            ),
          );
        }
        _lastSizes = nextSizes;

        // 原位置占位符：竖向拖动时卡片被抬起来，起手处的格子先留一个浅色印子；
        // **拖够距离**（movedAway）才淡出。横向拖动是在原位改尺寸，不留占位符。
        final placeholder =
            drag == null || drag.axis == _DragAxisKind.horizontal
            ? null
            : drag.origin;

        return GestureDetector(
          // 空白处点击：退出整理。卡片自己会吸收点击，不会误触
          onTap: widget.editing ? () => widget.onEditingChanged(false) : null,
          behavior: HitTestBehavior.opaque,
          // 长按识别器常驻（不随整理状态增删）：长按卡片入口、整理态里按住再拖都走它
          onLongPressStart: _onLongPressStart,
          onLongPressMoveUpdate: _onLongPressMove,
          onLongPressEnd: _onLongPressEnd,
          onLongPressCancel: _onLongPressCancel,
          child: AnimatedSize(
            duration: _sizeAnim,
            curve: _sizeCurve,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            child: SizedBox(
              key: _stackKey,
              width: double.infinity,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (placeholder != null)
                    Positioned.fromRect(
                      rect: placeholder,
                      child: IgnorePointer(
                        child: AnimatedSlide(
                          // 抬起来的时候占位符微微下沉（像卡片被从格子里拿起来）
                          offset: drag!.movedAway
                              ? const Offset(0, 0.04)
                              : Offset.zero,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          child: AnimatedOpacity(
                            opacity: drag.movedAway ? 0 : 1,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            child: _placeholder(),
                          ),
                        ),
                      ),
                    ),
                  ...cards,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 把卡片内容固定成**目标尺寸**再交给外面的补间卡框裁切。
  ///
  /// 直接用 AnimatedPositioned 时，子内容每帧都按「当前中间尺寸」重新排版：
  /// 放大过程里文字会先挤压再弹开，收缩过程中又会瞬间跳成小卡片排版。
  /// 这里让内容一次按最终尺寸排好、居中放在会补间的卡框里，长出 / 收回都跟着框走。
  Widget _framed({required Rect rect, required Widget child}) => ClipRRect(
    borderRadius: BorderRadius.circular(cardRadius),
    clipBehavior: Clip.hardEdge,
    child: OverflowBox(
      alignment: Alignment.center,
      minWidth: rect.width,
      maxWidth: rect.width,
      minHeight: rect.height,
      maxHeight: rect.height,
      child: child,
    ),
  );

  Rect? _draggedRect(_DragState? drag, _Placement placement) {
    if (drag == null) return null;
    final local = _toLocal(drag.pointer);
    if (local == null) return null;
    return (local - drag.grab) & drag.sizePx;
  }

  Widget _card(
    BuildContext context, {
    required FlexibleGridItem item,
    required bool isDragged,
    required bool isResizing,
  }) {
    Widget content = item.builder(context, item.size, widget.editing);

    if (isDragged) {
      content = IgnorePointer(
        child: Transform.scale(
          scale: 1.03,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(cardRadius),
              boxShadow: [
                BoxShadow(
                  color: SemColors.accent.withValues(alpha: 0.22),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: content,
          ),
        ),
      );
    } else if (widget.editing) {
      // 整理态里不用再等长按：按下直接拖；空白点击交给外层退出。
      // 把 touchSlop 调小，卡片拖动会先于列表滚动接受手势——否则竖着拖卡片
      // 会输给列表的竖向滚动（它的阈值只有 18，而 pan 默认要 36），变成滚页面。
      content = _eagerGestures(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 从按下的那一点算起：整理态里一拖就跟手，不会先丢掉手势识别前的那段位移
          dragStartBehavior: DragStartBehavior.down,
          // 整理态点卡片 = 选中它（顶部尺寸条作用于选中的这张）
          onTap: () => widget.onSelected?.call(item.id),
          onPanStart: (details) => _startPanDrag(item, details.globalPosition),
          onPanUpdate: (details) => _updateDrag(details.globalPosition),
          onPanEnd: (_) => _endDrag(),
          onPanCancel: _cancelDrag,
          child: content,
        ),
      );
    }

    final selected = widget.editing && widget.selectedId == item.id;
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
        // 只给选中的卡片显示缩放弧线（ColorOS 也是长按哪张、哪张出现角标）；
        // 调用方还没选中任何卡片时退化成每张都显示，保证有入口。
        // **1x1 也保留**：它是唯一能「拖一次就放大回去」的手势。
        if (widget.editing &&
            !isDragged &&
            (widget.selectedId == null || selected))
          Positioned(right: 0, bottom: 0, child: _resizeHandle(item)),
        if (isResizing)
          Positioned(
            left: 6,
            bottom: 6,
            child: IgnorePointer(
              child: Capsule(item.size.label, color: SemColors.accent),
            ),
          ),
      ],
    );
  }

  /// 整理态的手势要先于列表滚动被识别：缩小 [MediaQueryData.gestureSettings] 的
  /// touchSlop，pan 的接受阈值就从 36 降到 1，比列表的 18 更早赢得手势竞技场。
  Widget _eagerGestures(Widget child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(gestureSettings: const DeviceGestureSettings(touchSlop: 0.5)),
    child: child,
  );

  Widget _resizeHandle(FlexibleGridItem item) {
    // 卡片越小、角标越小：1x1 只有 55×59，用 34 的角标会吃掉半个卡面，
    // 既盖住图标又跟「按住卡片拖动」抢手势。
    final tiny = item.size == GridCardSize.single;
    final small = item.size.rows == 1;
    final hit = tiny ? 22.0 : (small ? 26.0 : 38.0);
    final paint = tiny ? 16.0 : (small ? 22.0 : 34.0);
    return _eagerGestures(
      GestureDetector(
        key: ValueKey<String>('fgrid-handle:${item.id}'),
        behavior: HitTestBehavior.opaque,
        // 从按下的那一点算起：识别出手势之前滑过的那段也要计入缩放，
        // 快速一拖不会出现「松手了尺寸还没变」。
        dragStartBehavior: DragStartBehavior.down,
        // 点角标 = 选中这张卡；不要冒泡成「退出整理」
        onTap: () => widget.onSelected?.call(item.id),
        onPanStart: (details) => _startResize(item, details.globalPosition),
        onPanUpdate: (details) => _updateResize(details.globalPosition),
        onPanEnd: (_) => _endResize(),
        onPanCancel: _endResize,
        child: SizedBox(
          width: hit,
          height: hit,
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: CustomPaint(
                size: Size(paint, paint),
                painter: _CornerArcPainter(
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

  /// 原地占位符：卡片被抬起来后留在它原来的格子里，拖开之后淡出。
  Widget _placeholder() => DecoratedBox(
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

/// ColorOS 风格的右下角「白弧」缩放角标：贴着卡片圆角的两道圆弧。
class _CornerArcPainter extends CustomPainter {
  const _CornerArcPainter({required this.color, required this.glow});

  final Color color;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width - 2;
    final rect = Rect.fromCircle(
      center: Offset(size.width, size.height),
      radius: radius,
    );
    canvas.drawArc(
      rect,
      math.pi,
      math.pi / 2,
      false,
      Paint()
        ..color = glow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      rect,
      math.pi,
      math.pi / 2,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CornerArcPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.glow != glow;
}

/// 一次排版结果：卡片 + 在 6 列网格里的起始行列 + 像素矩形（含内边距）。
class _Placement {
  const _Placement({
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

class _DragState {
  _DragState({
    required this.itemId,
    required this.item,
    required this.size,
    required this.sizePx,
    required this.grab,
    required this.pointer,
    required this.origin,
    required this.originIndex,
    required this.insert,
  }) : startPointer = pointer;

  final String itemId;

  /// 起拖时的卡片（含尺寸与顺序位置）：横向滑改尺寸时以它的尺寸为基准。
  final FlexibleGridItem item;

  final GridCardSize size;
  final Size sizePx;

  /// 手指相对卡片左上角的偏移（宫格本地坐标）：跟手时保持起手点不变。
  final Offset grab;

  /// 起拖时卡片在网格里的矩形 / 它在顺序里的下标：原地按住时按这两个还原布局。
  final Rect origin;
  final int originIndex;

  /// 起拖时的指针位置：用来判断「拖出去多远才算真的挪开」。
  final Offset startPointer;

  Offset pointer;
  int insert;

  /// 方向锁：一次拖动只做一件事（换位置 / 换尺寸），由第一段位移的
  /// 主导轴向决定，中途不再切换。
  _DragAxisKind? axis;

  /// 横向滑的连续档位（正 = 往右变大）与预览尺寸。
  int steps = 0;
  GridCardSize? previewSize;

  /// 已经拖开（超过 [_moveAwayThreshold]）：邻居才让位、占位符才淡出。
  bool movedAway = false;
}

class _ResizeState {
  _ResizeState({
    required this.itemId,
    required this.start,
    required this.current,
    required this.startPx,
    required this.startPointer,
  });

  final String itemId;
  final GridCardSize start;
  GridCardSize current;
  final Size startPx;
  final Offset startPointer;
}
