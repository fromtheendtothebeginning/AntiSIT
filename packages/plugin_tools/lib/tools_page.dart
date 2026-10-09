import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';

/// 工具宫格：卡片全部由工具插件贡献，这里只负责排版、预取与排序。
///
/// 排序结果存在注册表里（`plugin_tool_order`，按插件 id 记），所以启停插件、
/// 升级 App 都不会把用户排好的位置弄丢。
class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
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
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ToolOrderPage()));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tools = PluginRegistry.I.toolCards;
    return Scaffold(
      appBar: AppBar(
        title: const Text('工具'),
        actions: [
          if (tools.length > 1)
            IconButton(
              onPressed: _openSorter,
              icon: const Icon(Icons.swap_vert_rounded),
              tooltip: '排序',
            ),
        ],
      ),
      // 自己监听注册表：启停插件/改排序后立刻重排，不用等壳层来重建
      body: ListenableBuilder(
        listenable: PluginRegistry.I,
        builder: (context, _) => _grid(context, PluginRegistry.I.toolCards),
      ),
    );
  }

  Widget _grid(BuildContext context, List<PluginTool> tools) {
    final scheme = Theme.of(context).colorScheme;
    return LoginGate(
        child: tools.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    '没有启用任何工具。到「我的 → 插件管理」里打开需要的工具即可。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: SemColors.textMuted, height: 1.7),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                children: [
                  GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.42,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final t in tools)
                        AppCard(
                          onTap: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => t.open()))
                              .then((_) => setState(() {})),
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: t.color.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(t.icon, color: t.color, size: 24),
                              ),
                              const Spacer(),
                              Text(t.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(
                                t.subtitle(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: scheme.outline),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('工具排序'),
        actions: [
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
            child: Text('按住右侧手柄上下拖动，松手即生效（工具页立刻跟着变）',
                style: TextStyle(fontSize: 12, color: SemColors.textMuted, height: 1.5)),
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
                  title: Text(tool.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(tool.subtitle(), style: const TextStyle(fontSize: 12)),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.drag_handle_rounded, color: SemColors.textMuted),
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
