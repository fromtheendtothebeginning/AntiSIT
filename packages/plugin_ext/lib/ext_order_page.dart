import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';

import 'ext_icon.dart';
import 'extension_item.dart';
import 'extension_store.dart';

/// 拓展排序页：按住右侧手柄上下拖，松手即存（拓展页的宫格立刻跟着变）。
///
/// 用整页而不是底部弹层：弹层自带「下拉关闭」手势，会跟拖拽手柄抢
/// （与「工具排序」同一个理由）。
class ExtensionOrderPage extends StatefulWidget {
  const ExtensionOrderPage({super.key});

  @override
  State<ExtensionOrderPage> createState() => _ExtensionOrderPageState();
}

class _ExtensionOrderPageState extends State<ExtensionOrderPage> {
  ExtensionStore get _store => ExtensionStore.I;

  /// 本地副本：拖拽过程中先动它，松手再写回清单。
  late List<ExtensionItem> _items = _store.items;

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      _items.insert(newIndex, _items.removeAt(oldIndex));
    });
    _store.setOrder([for (final e in _items) e.id]);
  }

  Future<void> _reset() async {
    await _store.setOrder(const []);
    if (mounted) setState(() => _items = _store.items);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('拓展排序'),
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
            child: Text('按住右侧手柄上下拖动，松手即生效（拓展页立刻跟着变）；新加的拓展排在最后',
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
                final e = _items[i];
                return ListTile(
                  key: ValueKey(e.id),
                  leading: ExtIcon(item: e, size: 20),
                  title: Text(e.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(e.urlLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
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
