import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';

/// 工具宫格：卡片全部由工具插件贡献，这里只负责排版、预取与整理。
///
/// 整理（长按 / 标题栏「整理」）后可以：
/// * 直接拖卡片换位置（顺序存在注册表里，重启不丢）；
/// * 顶部尺寸条在 1×1 / 1×3 / 2×3（默认）/ 2×2 间切换，或拖右下角弧线细调（尺寸也落在本机）。
class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  /// 是否处于整理状态：显示尺寸条与缩放角标、卡片可直接拖动。
  bool _editing = false;

  /// 当前选中的工具卡片（顶部尺寸条作用于它）。
  String? _selectedCardId;

  @override
  void initState() {
    super.initState();
    _prefetch();
  }

  /// 预取各工具插件的卡面速览（电费余额、二课学分…），拿不到就保持默认副标题。
  Future<void> _prefetch() async {
    if (!AppState.I.loggedIn) return;
    await PluginRegistry.I.prefetchTools();
    if (mounted) setState(() {});
  }

  Future<void> _openSorter() async {
    // 用整页而不是底部弹层：弹层自带「下拉关闭」手势，会跟拖拽手柄抢
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ToolOrderPage()));
    if (mounted) setState(() {});
  }

  void _setEditing(bool value) {
    if (_editing == value) return;
    setState(() {
      _editing = value;
      if (value) {
        // 从「整理卡片」按钮进来时先选第一张，尺寸条马上可用；长按入口随后会改成被按住那张。
        final entries = PluginRegistry.I.toolEntries;
        _selectedCardId = entries.isEmpty ? null : entries.first.$1;
      } else {
        _selectedCardId = null;
      }
    });
  }

  void _selectCard(String id) {
    if (!_editing || _selectedCardId == id) return;
    setState(() => _selectedCardId = id);
  }

  @override
  Widget build(BuildContext context) {
    final tools = PluginRegistry.I.toolCards;
    return Scaffold(
      appBar: AppBar(
        title: const Text('工具'),
        actions: [
          if (_editing)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: () => _setEditing(false),
                style: TextButton.styleFrom(
                  foregroundColor: SemColors.accent,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('完成'),
              ),
            )
          else ...[
            if (tools.length > 1 || PluginRegistry.I.hasCustomToolSizes)
              IconButton(
                onPressed: _openSorter,
                icon: const Icon(Icons.swap_vert_rounded),
                tooltip: '排序',
              ),
            if (tools.isNotEmpty)
              IconButton(
                onPressed: () => _setEditing(true),
                icon: const Icon(Icons.dashboard_customize_outlined),
                tooltip: '整理卡片',
              ),
          ],
        ],
      ),
      // 自己监听注册表：启停插件 / 换顺序 / 改尺寸后立刻重排，不用等壳层来重建
      body: ListenableBuilder(
        listenable: PluginRegistry.I,
        builder: (context, _) {
          final entries = PluginRegistry.I.toolEntries;
          final selectedId = entries.any((e) => e.$1 == _selectedCardId)
              ? _selectedCardId
              : null;
          final selectedSize = selectedId == null
              ? null
              : PluginRegistry.I.toolSize(selectedId);
          return LoginGate(
            child: entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        '没有启用任何工具。到「我的 → 插件管理」里打开需要的工具即可。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: SemColors.textMuted,
                          height: 1.7,
                        ),
                      ),
                    ),
                  )
                : GestureDetector(
                    // 点空白 / 列表下方退出整理。卡片自己在整理态里吸收点击，
                    // 宫格也有一层空白点击（点卡片缝里也能退），这里补上整页范围。
                    behavior: HitTestBehavior.translucent,
                    onTap: _editing ? () => _setEditing(false) : null,
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView(
                            // 底栏是玻璃浮层（壳层 Scaffold.extendBody）：底部多让出底栏这一截。
                            // 整理态时尺寸条就贴在底栏上方，这份留白交给它，别再重复叠一次。
                            padding: EdgeInsets.only(
                              bottom: _editing
                                  ? 12
                                  : 16 + MediaQuery.paddingOf(context).bottom,
                            ),
                            children: [
                              FlexibleCardGrid(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  4,
                                  12,
                                  8,
                                ),
                                items: [
                                  for (final (id, tool) in entries)
                                    FlexibleGridItem(
                                      id: id,
                                      size: PluginRegistry.I.toolSize(id),
                                      builder: (context, size, editing) =>
                                          _toolCard(
                                            context,
                                            tool,
                                            size,
                                            editing,
                                          ),
                                    ),
                                ],
                                selectedId: selectedId,
                                onSelected: _selectCard,
                                editing: _editing,
                                onEditingChanged: _setEditing,
                                onOrderChanged: (ids) =>
                                    PluginRegistry.I.setToolOrder(ids),
                                onSizeChanged: (id, size) =>
                                    PluginRegistry.I.setToolSize(id, size),
                              ),
                            ],
                          ),
                        ),
                        // 尺寸条放在页面下方、底栏上方：顶部那块地方留给标题，
                        // 单手握持时拇指正好够得着（顶栏那排按钮要伸上去）。
                        if (_editing)
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              12,
                              4,
                              12,
                              8 + MediaQuery.paddingOf(context).bottom,
                            ),
                            child: CardSizeBar(
                              size: selectedSize,
                              onChanged: (size) {
                                final id = selectedId;
                                if (id != null) {
                                  PluginRegistry.I.setToolSize(id, size);
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }

  /// 一张工具卡片：四种尺寸各自排版（1x1 小方格 / 1x3 横条 / 2x3 默认 / 2x2 竖卡）。
  Widget _toolCard(
    BuildContext context,
    PluginTool tool,
    GridCardSize size,
    bool editing,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final tile = size == GridCardSize.single;
    final bar = size == GridCardSize.wide;
    final tall = size == GridCardSize.tall;
    void open() => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => tool.open()))
        .then((_) {
          if (mounted) setState(() {});
        });

    if (tile) {
      // 1x1 小方格：**只显示图标**（居中，略放大）。这么小的一格放名字只会被截成
      // 两三个字，图标反而更好认；名称靠长按选中后顶部尺寸条那一行、或放大后再看。
      return AppCard(
        bottomGap: 0,
        radius: 14,
        padding: EdgeInsets.zero,
        onTap: editing ? null : open,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: tool.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(tool.icon, color: tool.color, size: 20),
          ),
        ),
      );
    }

    final iconBlock = Container(
      padding: EdgeInsets.all(tall || bar ? 7 : 8),
      decoration: BoxDecoration(
        color: tool.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(tall || bar ? 9 : 10),
      ),
      child: Icon(tool.icon, color: tool.color, size: tall || bar ? 20 : 24),
    );

    if (bar) {
      // 1x3 横条：图标在左、标题和状态在右，只占一行高
      return AppCard(
        bottomGap: 0,
        radius: 16,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        onTap: editing ? null : open,
        child: Row(
          children: [
            iconBlock,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tool.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tool.subtitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.25,
                      color: scheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final title = Text(
      tool.title,
      maxLines: tall ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: tall ? 13.5 : 15,
        height: tall ? 1.18 : 1.15,
      ),
    );
    final subtitle = Text(
      tool.subtitle(),
      maxLines: tall ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: tall ? 11 : 12,
        height: 1.3,
        color: scheme.outline,
      ),
    );

    return AppCard(
      // 宫格自己控制间距：卡片必须正好填满单元，否则拖起来会比占位框小一圈
      bottomGap: 0,
      radius: 16,
      padding: EdgeInsets.all(tall ? 10 : 14),
      onTap: editing ? null : open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          iconBlock,
          const Spacer(),
          title,
          const SizedBox(height: 2),
          subtitle,
        ],
      ),
    );
  }
}

/// 拖拽排序页：按住右侧手柄上下拖，松手即存（宫格立刻跟着变）。
class ToolOrderPage extends StatefulWidget {
  const ToolOrderPage({super.key});

  @override
  State<ToolOrderPage> createState() => _ToolOrderPageState();
}

class _ToolOrderPageState extends State<ToolOrderPage> {
  /// 本地副本：拖拽过程中先动它，松手再写回注册表。
  late List<(String, PluginTool)> _items = PluginRegistry.I.toolEntries;

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      _items.insert(newIndex, _items.removeAt(oldIndex));
    });
    PluginRegistry.I.setToolOrder([for (final e in _items) e.$1]);
  }

  Future<void> _reset() async {
    await PluginRegistry.I.setToolOrder(const []);
    if (mounted) setState(() => _items = PluginRegistry.I.toolEntries);
  }

  Future<void> _resetSizes() async {
    await PluginRegistry.I.resetToolSizes();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('工具排序'),
        actions: [
          if (PluginRegistry.I.hasCustomToolSizes)
            TextButton(
              onPressed: _resetSizes,
              child: const Text('重置大小', style: TextStyle(fontSize: 13)),
            ),
          TextButton(
            onPressed: _reset,
            child: const Text('恢复默认', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
            child: Text(
              '按住右侧手柄上下拖动，松手即生效；工具页里长按卡片进入整理后，顶部尺寸条可在 1×1 / 1×3 / 2×3 / 2×2 间切换，也能拖右下角弧线细调',
              style: TextStyle(
                fontSize: 12,
                color: SemColors.textMuted,
                height: 1.5,
              ),
            ),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              padding: EdgeInsets.zero,
              itemCount: _items.length,
              onReorder: _onReorder,
              itemBuilder: (context, i) {
                final (pluginId, tool) = _items[i];
                return ListTile(
                  key: ValueKey(pluginId),
                  leading: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: tool.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(tool.icon, color: tool.color, size: 20),
                  ),
                  title: Text(
                    tool.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    tool.subtitle(),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: SemColors.textMuted,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
