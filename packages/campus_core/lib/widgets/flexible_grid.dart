import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'glass_widgets.dart';
import 'theme_palette.dart';

/// 卡片在 6 列基础网格上的占位：**行数 × 列数**（`2x3` = 2 行 × 3 列）。
///
/// 尺寸是**一套可扩展的档位目录**（[catalog]），不是写死的几种：
/// 新增一档只要往 [catalog] 里加一个 [GridCardSpec] 并补上它自己的排版，
/// 尺寸条、缩放手势吸附、落盘解析都会自动跟着支持。
///
/// 现有档位（行×列）：
/// * [single]  `1x1`：最小的一格（约 1/6 屏宽 × 59dp），只放图标；
/// * [wide]    `1x3`：1 行 × 3 列——半屏宽的横条；
/// * [narrow]  `2x1`：2 行 × 1 列——**窄竖条**（图标在上、竖排少量文字）；
/// * [standard]`2x3`：2 行 × 3 列——**默认大小**（半屏宽 × 128dp）；
/// * [tall]    `2x2`：2 行 × 2 列——1/3 屏宽的竖卡。
///
/// 行高由 [FlexibleCardGrid.unitHeight] 决定（默认 59dp）：2 行 + 1 个间距 = 128dp，
/// 与旧宫格默认卡片高度一致；宽度按剩余宽度均分 6 列，3 列恰好是旧卡片的半屏宽。
@immutable
class GridCardSize {
  const GridCardSize(this.rows, this.columns)
    : assert(rows >= 1 && rows <= maxRows),
      assert(columns >= 1 && columns <= maxColumns);

  /// 高度最多几行（网格总共就这么多行）。
  static const int maxRows = 2;

  /// 网格一共 6 列，最宽的档位是 3 列（半屏）。
  static const int maxColumns = 3;

  /// 高度占几行（1~[maxRows]）。
  final int rows;

  /// 宽度占几列（1~[maxColumns]）。
  final int columns;

  // ==================== 档位目录 ====================

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

  /// **全部可选档位**（尺寸条按这个顺序排）。
  ///
  /// 加一种尺寸就往这里加一项，并在各页 `_card` 里按 [kind] 补上对应排版；
  /// 尺寸条、缩放吸附、落盘解析都是遍历这个目录的，不用再改别处。
  static const List<GridCardSize> presets = <GridCardSize>[
    single,
    wide,
    narrow,
    standard,
    tall,
  ];

  /// 按「占几格」从小到大排：连续缩放时按这个顺序一档一档吸附
  /// （1×1 = 1 格 → 2×1 = 2 格 → 1×3 = 3 格 → 2×2 = 4 格 → 2×3 = 6 格）。
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

  /// 尺寸条上那个小预览的宽高（按行×列比例，封顶 22×16）。
  ({double w, double h}) get previewBox => (
        w: math.max(9, math.min(22, columns * 8)).toDouble(),
        h: math.max(8, math.min(16, rows * 7)).toDouble(),
      );

  /// 显示用标签（`2×3`，行×列）。
  String get label => '$rows×$columns';

  /// 落盘用的稳定 key（`2x3`，行×列）：ASCII，别跟着显示文案改。
  String get key => '${rows}x$columns';

  /// 解析落盘值；认不出来就回落到 [fallback]。
  ///
  /// 遍历 [presets] 而不是 switch：以后往目录里加档位，这里自动就认了。
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

/// 一种卡片尺寸的**排版取向**：页面据此决定内容怎么排。
enum GridCardKind {
  /// 只放一个图标（最小格，放不下名字）。
  iconOnly,

  /// 横向：图标在左、文字在右（1 行多列的横条）。
  row,

  /// 纵向：图标在上、文字在下，而且**窄**（多行 1 列的竖条）。
  stack,

  /// 完整卡：图标 / 标题 / 副标题都在（2x2、2x3）。
  full,
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

/// ColorOS 风格的卡片尺寸切换条：选中卡片后，一排四档尺寸的缩略预览按钮。
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
            // 档位来自目录；flex: 0 = 按内容自然宽度排（不像 Expanded 那样抢走
            // 全部剩余空间），档位多到装不下时自己在条内横向滚动。
            Flexible(
              flex: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < GridCardSize.presets.length; i++) ...[
                      _SizeOption(
                        preset: GridCardSize.presets[i],
                        selected: size == GridCardSize.presets[i],
                        enabled: enabled,
                        onTap: () => onChanged(GridCardSize.presets[i]),
                      ),
                      if (i != GridCardSize.presets.length - 1)
                        const SizedBox(width: 5),
                    ],
                  ],
                ),
              ),
            ),
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
    // 预览形状按「行×列」比例算，加档位自动适配（不用再写三元表达式）
    final box = preset.previewBox;
    final w = box.w;
    final h = box.h;
    final label = '${preset.label} ${preset.specLabel}';
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

/// 可整理（长按拖动换位 / 尺寸切换条 / 拖右下角弧线连续缩放）的柔性宫格。
///
/// 排版：6 列基础网格 + 2D 首次适配装箱，卡片按传入顺序从左到右、从上到下找空位。
/// 尺寸只有 [GridCardSize.presets] 四种设计档位（1x1 / 1x3 / 2x3 / 2x2，行×列）。
///
/// **手势三段式，互不冲突**：
/// 1. **长按 = 拖动**：无论在普通态还是整理态，按住卡片不放就一直处于可拖动状态，
///    卡片悬浮跟手；它落点处的格子留成空位（占位框），下面和后面的卡片绕开它排，
///    所以悬浮卡片**正下方永远是空的**。拖到列表上下边缘会自动滚动。
/// 2. **松手 = 整理态**：松手后顺序落位，并进入整理态、选中这张卡（右下角出现缩放弧线）。
/// 3. **整理态短点击卡片 = 选中它准备改大小**；**拖右下角弧线 = 连续缩放**——
///    卡框跟手连续变大 / 变小，松手吸附到四档里最接近的那档。
///
/// 拖动与缩放彻底分开：拖动只换位置，缩放只改尺寸，两者不会在同一段手势里抢。
///
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

  /// 当前选中的卡片：尺寸切换条作用于它，也只有它显示右下角缩放弧线。
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

/// 拖动时被「占住」的格位：悬浮卡片下方要腾出的那块空位。
///
/// 排版时先把这块标成已占用，其余卡片绕着它流式排布——于是在手指下面
/// 始终是一个与卡片等大的洞，下面的卡片被推下去。
class _Reserved {
  const _Reserved({required this.row, required this.col, required this.size});

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

class _FlexibleCardGridState extends State<FlexibleCardGrid>
    with SingleTickerProviderStateMixin {
  static const int _columns = 6;
  static const double _maxEdgeScrollSpeed = 900; // px/s

  /// 换尺寸的过渡时长：比换位慢一点，卡片像被轻轻推着长开 / 收回
  ///（ColorOS 改小组件尺寸的那种手感）。
  ///
  /// 曲线不写在这里：实际用哪条由 [_SlotMotion] 按「上一段的速度方向」挑
  /// （同向接着冲 / 反向先收速度），这样才能在动画中途改目标时保持动量。
  static const Duration _sizeAnim = Duration(milliseconds: 520);

  /// 只是换位置的过渡（邻居让位）：短一点，避免整页跟着「飘」。
  static const Duration _moveAnim = Duration(milliseconds: 300);

  /// 拖出去多远才算「真的挪开」：低于这个距离时卡片还算在原位，
  /// 邻居不让位、占位框也留在起手处（避免轻轻一碰就整页重排）。
  static const double _moveAwayThreshold = 14;

  /// 缩放起手的死区：按住弧线后位移小于它不缩放（防手抖）。
  static const double _resizeDeadZone = 3;

  /// 整个排版区的 RenderBox：把手指的全局坐标换算成宫格坐标。
  final GlobalKey _stackKey = GlobalKey();

  /// 最近的竖向滚动容器（工具栏 / 拓展页都在可滚动页面里，拖到边缘要自己滚）。
  ScrollPosition? _scrollPos;

  /// 拖动中：卡片悬在手指下，落点在它正下方留一块空位。
  _DragState? _drag;

  /// 缩放中：手柄跟手，尺寸连续变化，松手吸附到最近档位。
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

  /// 真正参与排版的卡片（基准顺序 + 尚未回写的本地覆盖）。
  ///
  /// **被拖动 / 正在缩放的那张都不在流里**：拖动时它悬在手指下，
  /// 缩放着它本体定在原处，两者都只用一个「占位背景」参与排版，
  /// 其余卡片被这块背景推开（[_reservedSlot]）。
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

  /// 当前要占住的格位（悬浮卡片下方那块空位）。
  ///
  /// 位置由**落点下标**决定：按「其余卡片 + 被拖卡片插到该下标」重新排版，
  /// 取被拖卡片落到的格子。于是空位与松手后的真实落点始终一致。
  /// 还没拖开时占起手位（布局保持原样）。
  _Reserved? _reservedSlot() {
    final drag = _drag;
    if (drag != null) {
      final origin = _Reserved(
        row: drag.originRow,
        col: drag.originCol,
        size: drag.size,
      );
      if (!drag.movedAway) return origin;
      final drop = _dropPoint(drag);
      if (drop == null) return origin;
      return _slotForDrop(drag, drop);
    }

    // 缩放中：占住它自己的槽位，尺寸取「排斥用的尺寸」——
    // 缩小时按最近的档位（邻居正常靠拢），放大时按最近的最大档位
    // （先把地方占足，邻居提前让开，不会跟长大的卡片重叠）。
    final resize = _resize;
    if (resize != null) {
      return _Reserved(
        row: resize.originRow,
        col: resize.originCol,
        size: resize.reserve,
      );
    }
    return null;
  }

  /// 缩放时「排斥用的尺寸」：
  ///
  /// * **缩小**（拖出来的尺寸比最近那档小）：用最近那档 —— 邻居按常规往里靠；
  /// * **放大**（任一方向已经超出最近那档）：用**能装下当前尺寸的最小档位**，
  ///   宁可多占一点，也不让邻居和正在长大的卡片重叠。
  GridCardSize _reserveFor(Size px, GridCardSize start) {
    final nearest = _nearestPreset(px);
    final nearestPx = _presetPx(nearest);
    final overflow =
        px.width > nearestPx.width + 0.5 || px.height > nearestPx.height + 0.5;
    if (!overflow) return nearest;

    final candidates = [
      for (final preset in GridCardSize.byArea)
        if (_presetPx(preset).width >= px.width - 0.5 &&
            _presetPx(preset).height >= px.height - 0.5)
          preset,
    ]..sort((a, b) => (a.rows * a.columns).compareTo(b.rows * b.columns));
    return candidates.isEmpty ? nearest : candidates.first;
  }

  /// 某一档的像素尺寸（宽 × 高）。
  Size _presetPx(GridCardSize size) {
    final gap = widget.spacing;
    return Size(
      size.columns * _colWidth + (size.columns - 1) * gap,
      size.rows * widget.unitHeight + (size.rows - 1) * gap,
    );
  }

  /// 拖动的**落点**（宫格本地坐标 = 悬浮卡片的中心）。
  ///
  /// 不能用指尖坐标：手指按在卡片上的位置是随机的（左上、右下都常见），
  /// 用指尖算「插到谁前面」会跟眼睛看到的悬浮卡片位置对不上。
  /// 这里用卡片中心，插入判定和占位框都按它算，三者永远一致。
  Offset? _dropPoint(_DragState drag) {
    final local = _toLocal(drag.pointer);
    if (local == null) return null;
    final topLeft = local - drag.grab;
    return topLeft + drag.sizePx.center(Offset.zero);
  }

  /// 把被拖卡片插到指针处的下标，重排一次，取它落到的格子。
  _Reserved _slotForDrop(_DragState drag, Offset drop) {
    final others = [
      for (final item in _baseItems())
        if (item.id != drag.itemId) item,
    ];
    final index = _dropIndexFor(drop, others).clamp(0, others.length);
    final sequence = <FlexibleGridItem>[...others]
      ..insert(index, drag.item);
    final layout = _pack(sequence, _colWidth);
    for (final placement in layout) {
      if (placement.item.id == drag.itemId) {
        return _Reserved(
          row: placement.row,
          col: placement.col,
          size: drag.size,
        );
      }
    }
    return _Reserved(
      row: drag.originRow,
      col: drag.originCol,
      size: drag.size,
    );
  }

  /// 指针落在「除被拖卡片以外」的哪两张之间：按阅读顺序，先看是否在这一行
  /// （落在卡片上下沿之间），同一行再按左右半边决定插在它前面还是后面。
  int _dropIndexFor(Offset local, List<FlexibleGridItem> others) {
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

  /// 插入落点：把被拖卡片的尺寸也占住，下面的卡片被推开。
  ///
  /// 与 [_pack] 相同的 2D 首次适配，只是**先占位**再排其余卡片：占位块周围
  /// 的卡片会绕开它流动，于是悬浮卡片正下方始终是空的（这就是「下方腾出空位」）。
  List<_Placement> _packReserved(
    List<FlexibleGridItem> items,
    _Reserved reserved,
    double colWidth,
  ) {
    final occupied = <int, List<bool>>{};

    void mark(int row, int col, GridCardSize size) {
      // 夹住边界：占位块可能贴着右边缘（例如 4 列宽的卡在放大中途），
      // 越界写数组会直接抛 RangeError。
      final lastCol = math.min(_columns, col + size.columns);
      final firstCol = math.max(0, col);
      for (var r = math.max(0, row); r < row + size.rows; r++) {
        final line = occupied.putIfAbsent(
          r,
          () => List<bool>.filled(_columns, false),
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

    final out = <_Placement>[];
    for (final item in items) {
      final size = item.size;
      var placed = false;
      for (var row = 0; !placed; row++) {
        for (var col = 0; col + size.columns <= _columns; col++) {
          if (!isFree(row, col, size)) continue;
          mark(row, col, size);
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
    // 起手格位：用当前排版里这张卡的位置反推（它此刻一定在 placements 里）
    final placement = _placements
        .where((p) => p.item.id == item.id)
        .firstOrNull;
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
        originRow: placement?.row ?? 0,
        originCol: placement?.col ?? 0,
      );
    });
    _syncEdgeScroll();
  }

  /// 长按拖动 = **只换位置**。
  ///
  /// 无论普通态还是整理态，只要手指不松就一直可拖：卡片悬在手指下，
  /// 落点格位由 [_reservedSlot] 占住，其余卡片绕开它排（正下方始终是空的）。
  /// 超过 [_moveAwayThreshold] 才把占位从起手位挪到落点，
  /// 避免轻轻一碰就整页重排。
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

  /// 松手：顺序落位，并**停在整理态**选中这张卡（右下角出现缩放弧线，
  /// 用户可以接着改大小）。点空白处才退出整理。
  void _endDrag() {
    final drag = _drag;
    if (drag == null) return;
    _stopEdgeScroll();

    // 没拖开就松手 = 纯长按：**必须保持原顺序**。
    // （按落点算下标会把它判到后面去，因为参照布局里已经没有它自己了。）
    final baseIds = [for (final item in _baseItems()) item.id];
    final movedAway = drag.movedAway;
    final local = movedAway ? _dropPoint(drag) : null;
    final others = _displayItems(); // 已经不含被拖的那张
    final insertAt = local == null
        ? -1
        : _dropIndexFor(
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

    final changed = !_sameOrder(ids, baseIds);
    setState(() {
      _drag = null;
      if (changed) _pendingOrder = List<String>.of(ids);
    });
    if (changed) {
      widget.onOrderChanged(ids);
      HapticFeedback.lightImpact();
    }
    // 松手即进入整理态并选中这张（尺寸条与缩放弧线都指向它）。
    // 顺序：先进整理态再选中 —— 反过来会被页面的「进整理自动选第一张」覆盖掉。
    if (!widget.editing) widget.onEditingChanged(true);
    widget.onSelected?.call(drag.itemId);
  }

  void _cancelDrag() {
    if (_drag == null) return;
    _stopEdgeScroll();
    setState(() => _drag = null);
  }

  // ==================== 弧线缩放（连续跟手 + 松手吸附） ====================

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
        startPx: placement.rect.size,
        startPointer: global,
        originRow: placement.row,
        originCol: placement.col,
      );
    });
    HapticFeedback.selectionClick();
  }

  /// 跟手缩放：手指位移直接加到起手像素尺寸上，算出**最近档位背景**。
  ///
  /// 注意本体不动：这里只更新 [ _ResizeState.snapped ]（背景块大小），
  /// 邻居按它让位；卡框本体钉在起手格位上，直到松手才整体落到新尺寸。
  /// 这就是「调整大小优先级最高、滑动期间组件本体不动」。
  void _updateResize(Offset global) {
    final resize = _resize;
    if (resize == null) return;
    final delta = global - resize.startPointer;
    if (!resize.started) {
      if (delta.distance < _resizeDeadZone) return;
      resize.started = true;
    }
    // 连续像素尺寸：宽高各自跟手，并夹在设计档位的范围内
    final minW = _colWidth;
    final maxW = 3 * _colWidth + 2 * widget.spacing;
    final minH = widget.unitHeight;
    final maxH = 2 * widget.unitHeight + widget.spacing;
    final width = (resize.startPx.width + delta.dx).clamp(minW, maxW);
    final height = (resize.startPx.height + delta.dy).clamp(minH, maxH);
    final nextPx = Size(width, height);
    final snapped = _nearestPreset(nextPx);
    final reserve = _reserveFor(nextPx, resize.start);
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
      if (changed) _pendingSizes[resize.itemId] = target;
    });
    if (changed) {
      widget.onSizeChanged(resize.itemId, target);
      HapticFeedback.lightImpact();
    }
  }

  /// 连续尺寸 → 最接近的设计档位（按像素距离，宽高各自按列/行步长归一）。
  GridCardSize _nearestPreset(Size px) {
    final gap = widget.spacing;
    final colStride = math.max(1.0, _colWidth + gap);
    final rowStride = math.max(1.0, widget.unitHeight + gap);
    var best = GridCardSize.presets.first;
    var bestDistance = double.infinity;
    for (final preset in GridCardSize.byArea) {
      final w = preset.columns * _colWidth + (preset.columns - 1) * gap;
      final h = preset.rows * widget.unitHeight + (preset.rows - 1) * gap;
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

  // ==================== 拖动到边缘自动滚动 ====================

  void _syncEdgeScroll() {
    final drag = _drag;
    if (drag == null) {
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
    // 内容滚了：手指没动，但换算到宫格坐标系的位置变了——重画一次，
    // 让占位块跟着指针下方的格子走。
    setState(() {});
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
        final reserved = _reservedSlot();
        // 先把占位块占住，其余卡片绕着它排 —— 悬浮卡片正下方永远是空的。
        final placements = reserved == null
            ? _pack(display, colWidth)
            : _packReserved(display, reserved, colWidth);
        _placements = placements;
        final drag = _drag;
        final resize = _resize;

        // 占位框（悬浮卡片下方那块空位）也计入高度，否则拖到最下面会画不下。
        var height = _gridHeight(placements);
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

        final cards = <Widget>[];
        final nextSizes = <String, Size>{
          for (final p in placements) p.item.id: p.rect.size,
        };

        for (final placement in placements) {
          final item = placement.item;
          // 卡框尺寸变了才播「跟随」动画（换档 / 邻居让位）。
          final previousSize = _lastSizes[item.id];
          final sizeChanged =
              previousSize != null && previousSize != placement.rect.size;
          cards.add(
            _SlotMotion(
              key: ValueKey<String>('fgrid:${item.id}'),
              target: placement.rect,
              // 换尺寸走慢一点、纯换位快一点；中途目标再变只换目标，
              // 动画带着当前速度继续（见 [_SlotMotion]）。
              duration: sizeChanged ? _sizeAnim : _moveAnim,
              child: _framed(
                layoutSize: _layoutSizeFor(item, placement.rect.size),
                child: _card(
                  context,
                  item: item,
                  isDragged: false,
                  isResizing: false,
                ),
              ),
            ),
          );
        }
        _lastSizes = nextSizes;

        // 缩放中：本体跟着手指**灵活缩放**（连续像素尺寸），
        // 虚线框画「最近的适配大小」，邻居按虚线框让位。
        if (resize != null) {
          final resizeItem = _itemById(resize.itemId);
          final bodyRect = _resizeBodyRect(resize);
          if (resizeItem != null && bodyRect != null) {
            nextSizes[resizeItem.id] = bodyRect.size;
            cards.add(
              _SlotMotion(
                key: ValueKey<String>('fgrid:${resizeItem.id}'),
                target: bodyRect,
                // 跟手：直接贴住目标，不播动画
                snap: true,
                duration: _sizeAnim,
                child: _framed(
                  // 卡面必须**铺满跟手框**：之前用档位尺寸（2x1 只有 55 宽）排版，
                  // 拖到 105 宽时右半边是空的，整张卡看着就暗淡、像被裁了一半。
                  // 这里按当前像素尺寸铺满，内部再按 layoutAs 用对应的档位排版。
                  layoutSize: bodyRect.size,
                  // 贴左上角：缩放时图标与文字的绝对位置不动，只有卡框边界在动。
                  anchorTopLeft: true,
                  child: _card(
                    context,
                    item: resizeItem,
                    isDragged: false,
                    isResizing: true,
                    layoutAs: _layoutPresetFor(bodyRect.size),
                  ),
                ),
              ),
            );
          }
        }

        // 被拖动的卡片不在 placements 里（它悬在手指下、不参与流式排版），
        // 这里单独按手指位置画在最上层。
        if (drag != null) {
          final dragItem = _itemById(drag.itemId);
          final dragRect = _draggedRect(drag);
          if (dragItem != null && dragRect != null) {
            nextSizes[dragItem.id] = dragRect.size;
            cards.add(
              _SlotMotion(
                key: ValueKey<String>('fgrid:${dragItem.id}'),
                target: dragRect,
                // 跟手：直接贴住目标，不播动画
                snap: true,
                duration: _moveAnim,
                child: _framed(
                  layoutSize: _layoutSizeFor(dragItem, dragRect.size),
                  child: _card(
                    context,
                    item: dragItem,
                    isDragged: true,
                    isResizing: false,
                  ),
                ),
              ),
            );
          }
        }

        // 占位背景：拖动时 = 悬浮卡片的落点；缩放时 = 最近档位的大小。
        // 两者都靠它把邻居推开。
        final showSlot = reservedRect != null && _slotVisible;

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
                  // 占位 / 目标框**永远压在最下层**：它只是「松手后会占多大」的提示，
                  // 主角是跟着手指走的卡片本体，两者绝不能抢。
                  if (showSlot)
                    Positioned.fromRect(
                      key: const ValueKey<String>('fgrid-slot'),
                      rect: reservedRect,
                      child: IgnorePointer(
                        child: _placeholder(dashed: resize != null),
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

  /// 内容排版的基准尺寸：取卡片**当前档位的完整尺寸**，不跟着中间像素走。
  ///
  /// 缩放过程中卡框是连续变的，内容始终按某一档的完整尺寸排一次：
  /// 这样不会按中间尺寸重排，也就不会出现 RenderFlex 溢出；
  /// 至于用哪一档排版（图标 / 文字大小），由 [_layoutPresetFor] 决定。
  Size _layoutSizeFor(FlexibleGridItem item, Size fallback) {
    if (fallback.width > 0 && fallback.height > 0) return fallback;
    final size = item.size;
    return Size(
      size.columns * _colWidth + (size.columns - 1) * widget.spacing,
      size.rows * widget.unitHeight + (size.rows - 1) * widget.spacing,
    );
  }

  /// 把卡片内容按**某一档的完整尺寸**排好，再交给会变形的卡框裁切。
  ///
  /// 直接用 AnimatedPositioned 时，子内容每帧都按「当前中间尺寸」重新排版：
  /// 放大过程里文字会先挤压再弹开，收缩过程中又会瞬间跳成小卡片排版。
  ///
  /// [anchorTopLeft] = false（默认）时内容居中：换档动画里卡框长开、内容居中缩放；
  /// = true 时内容**贴左上角**：缩放跟手过程中，图标与文字的绝对位置不动，
  /// 只有卡框边界在动——这正是「组件大小跟随手指、内部标签位置不动」。
  Widget _framed({
    required Size layoutSize,
    required Widget child,
    bool anchorTopLeft = false,
  }) => ClipRRect(
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

  /// 中间尺寸下该用哪一档的**排版模式**（图标大小、标题几行、留白多少都由它决定）。
  ///
  /// 取「能完整装进当前像素尺寸的最大一档」：这样内容既按最近的大档位排版
  /// （不会因为空间不够而 RenderFlex 溢出），又能在缩到一半时提前换成小档位
  /// 的排版——表现就是「图标、文字跟着卡片大小自由调整」，
  /// 而不是原来的大排版被裁掉一角。
  GridCardSize _layoutPresetFor(Size px) {
    var best = GridCardSize.presets.first;
    var bestArea = -1;
    for (final preset in GridCardSize.presets) {
      final box = _presetPx(preset);
      if (box.width > px.width + 0.5 || box.height > px.height + 0.5) continue;
      final area = preset.rows * preset.columns;
      if (area > bestArea) {
        best = preset;
        bestArea = area;
      }
    }
    if (bestArea >= 0) return best;
    // 比最小档还小（刚按下还没拖开）：用最小档排版，交给卡框裁切
    return GridCardSize.single;
  }

  /// 缩放时卡片本体的位置与尺寸：**左上角钉在起手格位上，宽高跟着手指连续变**。
  ///
  /// 所以缩放期间看到的是「卡片本身在灵活地变大 / 变小」，
  /// 虚线框才是「最近的适配大小」（松手后会落到那一档）。
  Rect? _resizeBodyRect(_ResizeState resize) {
    final origin = _rectFor(
      resize.originRow,
      resize.originCol,
      resize.start,
      _colWidth,
    );
    final px = resize.started ? resize.currentPx : resize.startPx;
    return Rect.fromLTWH(origin.left, origin.top, px.width, px.height);
  }

  /// 缩放中的卡片还够不够宽，能容下右上角的尺寸徽标（约 46×22）。
  /// 1×1 那种小格子放徽标会盖住图标，此时只靠虚线框表达目标大小。
  bool get _resizeBadgeFits {
    final resize = _resize;
    if (resize == null) return false;
    final px = resize.started ? resize.currentPx : resize.startPx;
    return px.width >= 110 && px.height >= 50;
  }

  /// 占位背景现在要不要显示：
  /// * 拖动中 —— 拖开之后（movedAway）才显出来；
  /// * 缩放中 —— 从手指离开死区起一直显示（这一块就是「最近的组件大小」）。
  bool get _slotVisible {
    final resize = _resize;
    if (resize != null) return resize.started;
    final drag = _drag;
    return drag != null && drag.movedAway;
  }

  Rect? _draggedRect(_DragState? drag) {
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
    GridCardSize? layoutAs,
  }) {
    // 缩放过程中按「最近能装下的那一档」排版：图标大小、标题行数、留白
    // 都跟着当前大小切换，而不是把大排版硬裁掉一块。
    Widget content = item.builder(
      context,
      layoutAs ?? item.size,
      widget.editing,
    );

    // 抬起中的卡片（拖动 / 缩放）要垫一层**实底**：
    // 卡片本身是白 55% 的半透明玻璃，直接压在虚线填充上会被染色，
    // 看上去比周围邻居暗一档。垫上「卡片色合成到页面底色」的实底后就与邻居同色，
    // 再配一圈更重的阴影，读起来是「被拎起来了」而不是「变暗了」。
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
      // 缩放中：卡片抬起一点点（阴影 + 轻微放大），跟手但不再挂拖动识别器，
      // 保证这段手势只改尺寸、绝不换位置。
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
    } else if (widget.editing) {
      // 整理态里卡片本体**只响应点击（选中）**，不再一按下就跟手拖动。
      //
      // 拖动统一由外层那个长按识别器负责：按住不放 → 抬起跟手拖动；
      // 短点 → 选中，之后拖右下角弧线改大小。
      // 这样「左右滑动」不会把卡片拖走，跟「调整大小」彻底分开——
      // 冲突的根源就是这里原本的即时 pan。
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 整理态点卡片 = 选中它（尺寸条作用于选中的这张，也可拖弧线改大小）
        onTap: () => widget.onSelected?.call(item.id),
        child: content,
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
        if (isResizing && _resizeBadgeFits)
          // 尺寸徽标浮在**右上角**：内容贴左上角排，左下角常被标题 / 副标题占满。
          // 卡片缩得很小时徽标会压住图标，所以只在够宽时才显示
          //（目标大小由虚线框 + 尺寸条表达，不缺这一处信息）。
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              child: Capsule(
                _resize?.label ?? item.size.label,
                color: SemColors.accent,
              ),
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
    // 最小格（只放图标）用最小角标；1 行高的档位（1x1 / 1x3）也用小的，
    // 否则 38 的角标会吃掉半个卡面，还跟「按住卡片拖动」抢手势。
    final tiny = item.size.kind == GridCardKind.iconOnly;
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

  /// 占位背景的装饰：
  /// * 拖动时 = 实心浅色块（卡片抬起后留下的落点）；
  /// * 缩放时 = **虚线框**（表示「松手后会变成这个大小」，不是卡片本体）。
  Widget _placeholder({bool dashed = false}) {
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
    // 缩放时的目标框靠**描边**表达，不靠填充：卡片本身是白 55% 的半透明玻璃，
    // 底下压一层明显的蓝填充会把它染色，看起来就比邻居「暗淡」。
    // 所以填充压到 6%（只用来勾出区域轮廓），信号交给加粗的虚线 + 外发光。
    return CustomPaint(
      painter: _DashedBoxPainter(
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

/// 一张卡片的「位置 + 尺寸」动画壳：
///
/// 目标 rect 变了就从**当前所在位置**继续走，而不是跳回起点重播——
/// 这是「播放期间又改变时按差项调整到新形态（保持动量）」。
///
/// 三个要点：
/// 1. **最短 0.2 秒**：时长夹到不小于 200ms；
/// 2. **差项起步**：新目标到来时起点 = 此刻屏幕上的位置，视觉连续、不跳；
/// 3. **动量**：用上一段的瞬时速度判断这次是「顺着冲」还是「被拉回来」，
///    同向用 easeOutCubic（接着冲）、反向用 easeInOutCubic（先收速度再走）。
class _SlotMotion extends StatefulWidget {
  const _SlotMotion({
    super.key,
    required this.target,
    required this.duration,
    required this.child,
    this.snap = false,
  });

  /// 这一帧排版算出来的目标矩形。
  final Rect target;

  /// true = 直接贴住目标不做动画（跟着手指走的本体用）。
  ///
  /// 它同时也是「类型统一」用的：跟手卡片和普通卡片都是 [_SlotMotion]，
  /// 只是 snap 不同——元素就不会在两者之间被销毁重建（否则 pan 手势会断）。
  final bool snap;

  /// 一次完整变化的时长（调用方给：换位 300ms / 换尺寸 520ms）。
  final Duration duration;

  final Widget child;

  /// 允许的最短动画时长（要求：不小于 0.2 秒）。
  static const Duration minDuration = Duration(milliseconds: 200);

  @override
  State<_SlotMotion> createState() => _SlotMotionState();
}

class _SlotMotionState extends State<_SlotMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _effective(widget.duration));

  /// 这一次变化的起点 / 终点。
  ///
  /// ⚠️ 必须在 initState 里赋值，不能用 `late ... = widget.target` 的惰性初始化：
  /// 那样 `_to` 会在**第一次被读到时**才求值（也就是 didUpdateWidget 里），
  /// 拿到的是新目标，比较永远相等 → 动画一次都不播（踩过）。
  late Rect _from;
  late Rect _to;

  @override
  void initState() {
    super.initState();
    _from = widget.target;
    _to = widget.target;
  }

  /// 上一段的瞬时速度（px/s）：下一次选曲线时用作动量。
  Offset _velocity = Offset.zero;

  Duration _effective(Duration d) =>
      d < _SlotMotion.minDuration ? _SlotMotion.minDuration : d;

  @override
  void didUpdateWidget(covariant _SlotMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.target == _to) return;
    if (widget.snap) {
      _controller.stop();
      _from = widget.target;
      _to = widget.target;
      _velocity = Offset.zero;
      _controller.value = 1;
      return;
    }
    // 差项：从「此刻屏幕上在哪」接着走，不回到上一段起点
    final current = _rectAt(_controller.value);
    final dt = _effective(widget.duration).inMicroseconds / 1000000;
    final slope = _slope(_curveFor(_velocity, current.center, widget.target.center),
        _controller.value);
    _velocity = (current.center - _from.center) * (slope / dt);
    _from = current;
    _to = widget.target;
    if ((_to.center - _from.center).distance < 0.5 &&
        (_to.size.width - _from.size.width).abs() < 0.5 &&
        (_to.size.height - _from.size.height).abs() < 0.5) {
      _controller.value = 1;
      return;
    }
    _controller.duration = _effective(widget.duration);
    _controller.forward(from: 0);
  }

  /// 曲线：**一律 easeInOutCubic**（慢-快-慢）。
  ///
  /// 原来「顺着冲」用 easeOutCubic 是错的：它在 520ms 里前 60ms 就走完 39%，
  /// 肉眼看就是「一瞬间跳过去」，完全看不出动画。easeInOutCubic 把位移摊满
  /// 整个时长，起手慢、收尾慢，才读得出「邻居滑过去」这件事。
  ///
  /// 动量没有丢：[_from] 取的是当前位置（差项起步），中途改目标不会回跳；
  /// 速度信息仍然用 [velocity] 记录，反向时收尾更软（见 [_effective]）。
  Curve _curveFor(Offset velocity, Offset from, Offset to) => Curves.easeInOutCubic;

  /// 曲线在 t 处的斜率（两段差分近似），只用来推算瞬时速度。
  double _slope(Curve curve, double t) {
    const h = 0.02;
    final a = (t - h).clamp(0.0, 1.0);
    final b = (t + h).clamp(0.0, 1.0);
    if (b <= a) return 0;
    return (curve.transform(b) - curve.transform(a)) / (b - a);
  }

  Rect _rectAt(double t) {
    if (t <= 0) return _from;
    if (t >= 1) return _to;
    final curve = _curveFor(_velocity, _from.center, _to.center);
    return Rect.lerp(_from, _to, curve.transform(t)) ?? _to;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      // child 不参与每帧重建：只有外面那层 Positioned 在动
      child: widget.child,
      builder: (context, child) {
        final rect = widget.snap || _controller.value >= 1
            ? _to
            : _rectAt(_controller.value);
        return Positioned.fromRect(rect: rect, child: child!);
      },
    );
  }
}
/// 虚线圆角框：缩放时用它画「松手后会变成这个大小」的背景。
///
/// 它是缩放过程中**唯一**能表达「目标尺寸」的东西（卡片本体是跟手的连续尺寸），
/// 所以要画得够显眼：粗虚线 + 半透明填充 + 外发光，浅色和深色卡面上都能一眼看到。
class _DashedBoxPainter extends CustomPainter {
  const _DashedBoxPainter({
    required this.color,
    required this.fill,
    required this.radius,
    this.glow = const Color(0x00000000),
    this.dash = 9,
    this.gap = 5,
    this.strokeWidth = 2.6,
  });

  final Color color;
  final Color fill;

  /// 外发光（画两遍：先粗淡的一层当光晕，再画实线）。
  final Color glow;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2 + 1;
    final rect = (Offset.zero & size).deflate(inset);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // 底色：让「松手后会占多大」这一块明显地浮起来
    canvas.drawRRect(rrect, Paint()..color = fill);

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();

    // 光晕：同一条路径画粗一点、淡一点
    if (glow.a > 0) {
      final halo = Paint()
        ..color = glow
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 2.6
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      for (final metric in metrics) {
        _dashPath(canvas, metric, halo);
      }
    }

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    for (final metric in metrics) {
      _dashPath(canvas, metric, stroke);
    }
  }

  // PathMetric 属于 dart:ui，这里不显式标类型（避免额外 import），交给推断
  void _dashPath(Canvas canvas, dynamic metric, Paint paint) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = math.min(distance + dash, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance = next + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBoxPainter old) =>
      old.color != color ||
      old.fill != fill ||
      old.glow != glow ||
      old.radius != radius ||
      old.dash != dash ||
      old.gap != gap ||
      old.strokeWidth != strokeWidth;
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

  /// 已经拖开（超过 [_moveAwayThreshold]）：才真正把占位挪到落点。
  /// 之前只是「抬起来」，布局不动，避免轻轻一碰就整页重排。
  bool movedAway = false;
}

class _ResizeState {
  _ResizeState({
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
