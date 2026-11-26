import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 选择弹窗的一项。
typedef AiPickerItem = ({String value, String title, Widget? leading});

/// 通用选择弹窗：提供商与模型共用同一形态。
class AiPickerDialog extends StatefulWidget {
  const AiPickerDialog({
    super.key,
    required this.title,
    required this.items,
    required this.current,
    this.badge,
    this.notes = const [],
    this.searchHint,
    this.allowCustom = false,
  });

  final String title;
  final List<AiPickerItem> items;
  final String? current;

  /// 右上角徽章（如提供商标识）。
  final String? badge;

  /// 需要额外说明的提示（拉取失败、当前值已失效等），用告警色。
  final List<String> notes;

  /// 非空时显示筛选框（长列表才好找）。
  final String? searchHint;

  /// 允许把筛选框里输入的任意字符串当作结果返回（用于手填模型 ID）。
  final bool allowCustom;

  @override
  State<AiPickerDialog> createState() => _AiPickerDialogState();
}

class _AiPickerDialogState extends State<AiPickerDialog> {
  final _filter = TextEditingController();
  final _listCtl = ScrollController();

  @override
  void dispose() {
    _filter.dispose();
    _listCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final raw = _filter.text.trim();
    final q = raw.toLowerCase();
    final list = q.isEmpty
        ? widget.items
        : widget.items
            .where((it) => it.title.toLowerCase().contains(q))
            .toList();
    // 允许手填时：筛选框里输入的内容若不是现成项，置顶一条「使用 …」
    final custom = widget.allowCustom &&
        raw.isNotEmpty &&
        !widget.items.any((it) => it.value == raw);

    // 弹窗高度自适应：放得下就不出现滚动，放不下才滚并常显滚动条。
    const rowH = 46.0; // dense ListTile 一行的大致高度
    final listRows = list.length + (custom ? 1 : 0);
    final chrome = 150.0 +
        (widget.searchHint != null ? 62.0 : 0) +
        widget.notes.length * 40.0;
    final screenH = MediaQuery.of(context).size.height;
    // 上限同时受屏幕比例与「标题+按钮+弹窗内边距」留白约束，避免内容把弹窗撑出屏幕
    final maxH = math.min(screenH * 0.6, screenH - 190);
    final wantH = math.min(maxH, math.max(160.0, chrome + listRows * rowH));
    final scrolls = listRows * rowH > wantH - chrome + 1;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          if (widget.badge != null)
            Capsule(widget.badge!, color: SemColors.accent),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      content: SizedBox(
        width: 380,
        height: wantH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final note in widget.notes) ...[
              _note(note),
              const SizedBox(height: 8),
            ],
            if (widget.searchHint != null) ...[
              TextField(
                controller: _filter,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                q.isEmpty
                    ? '共 ${list.length} 项'
                    : '匹配 ${list.length} / ${widget.items.length}',
                style: TextStyle(fontSize: 11, color: SemColors.textMuted),
              ),
              const SizedBox(height: 2),
            ] else
              Text(
                '共 ${widget.items.length} 项',
                style: TextStyle(fontSize: 11, color: SemColors.textMuted),
              ),
            Expanded(
              // 列表为空但有「使用输入值」这条时也要渲染，否则手填入口会消失
              child: (list.isEmpty && !custom)
                  ? Center(
                      child: Text(
                        '没有匹配的项',
                        style: TextStyle(
                          fontSize: 13,
                          color: SemColors.textMuted,
                        ),
                      ),
                    )
                  : Scrollbar(
                      // 需要滚动时才常显滚动条（可滚动的提示），放得下时不占视觉
                      thumbVisibility: scrolls,
                      controller: _listCtl,
                      child: ListView.builder(
                        controller: _listCtl,
                        padding: const EdgeInsets.only(right: 6),
                        itemCount: list.length + (custom ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (custom && i == 0) {
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: SemColors.accent,
                              ),
                              title: Text(
                                '使用「$raw」',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: SemColors.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onTap: () => Navigator.pop(context, raw),
                            );
                          }
                          final it = list[custom ? i - 1 : i];
                          final sel = it.value == widget.current;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: it.leading,
                            title: Text(
                              it.title,
                              style: TextStyle(
                                fontSize: 13,
                                color: SemColors.textPrimary,
                                fontWeight:
                                    sel ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                            trailing: sel
                                ? Icon(
                                    Icons.check,
                                    size: 18,
                                    color: SemColors.accent,
                                  )
                                : null,
                            onTap: () => Navigator.pop(context, it.value),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _note(String text) {
    final color = SemColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, height: 1.5),
      ),
    );
  }
}
