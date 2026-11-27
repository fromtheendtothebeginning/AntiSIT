import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'ext_dependency_plan.dart';

/// 树状下载界面：把「装应用插件 + 它的依赖」按拓扑顺序画成一棵树，
/// 每个节点显示下载 / 安装状态（待装 / 下载中 / 已装 / 已跳过 / 失败）。
class ExtDependencyDownloadSheet extends StatefulWidget {
  const ExtDependencyDownloadSheet({
    super.key,
    required this.rows,
    required this.run,
  });

  /// 计划好的树行（[extTreeRows] 的结果），界面按它铺层。
  final List<ExtTreeRow> rows;

  /// 真正执行安装：每完成一步回传一行，界面据此上色。
  final Future<void> Function(void Function(ExtTreeRow row) onStep) run;

  @override
  State<ExtDependencyDownloadSheet> createState() =>
      _ExtDependencyDownloadSheetState();
}

class _ExtDependencyDownloadSheetState
    extends State<ExtDependencyDownloadSheet> {
  late List<ExtTreeRow> _rows = widget.rows;
  bool _running = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _running = true);
    try {
      await widget.run((row) {
        if (!mounted) return;
        setState(() {
          _rows = [
            for (final r in _rows)
              if (r.node.id == row.node.id)
                ExtTreeRow(
                  node: r.node,
                  depth: r.depth,
                  needed: row.needed,
                  state: row.state,
                  error: row.error,
                )
              else
                r,
          ];
        });
      });
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _finished = true;
        });
      }
    }
  }

  int get _doneCount => _rows.where((r) => r.state == ExtTreeState.done).length;
  int get _neededCount => _rows.where((r) => r.needed).length;
  int get _failedCount =>
      _rows.where((r) => r.state == ExtTreeState.failed).length;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _finished
                        ? (_failedCount == 0 ? '安装完成' : '部分插件没装成功')
                        : '正在安装插件',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_finished)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('完成'),
                  ),
              ],
            ),
            if (_neededCount > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: LinearProgressIndicator(
                  value: _neededCount == 0 ? null : _doneCount / _neededCount,
                  minHeight: 3,
                ),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final r in _rows) _row(r)],
                ),
              ),
            ),
            if (_running)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '先装依赖插件，再装应用插件（拓扑顺序）',
                  style: TextStyle(fontSize: 11.5, color: SemColors.textMuted),
                ),
              ),
            for (final r in _rows.where(
              (r) => r.state == ExtTreeState.failed && r.error.isNotEmpty,
            ))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${r.node.name}：${r.error}',
                  style: TextStyle(fontSize: 11.5, color: SemColors.danger),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(ExtTreeRow row) {
    final indent = 14.0 * row.depth;
    final (icon, color) = switch (row.state) {
      ExtTreeState.pending => (
        Icons.hourglass_empty_rounded,
        SemColors.textMuted,
      ),
      ExtTreeState.downloading => (Icons.downloading_rounded, SemColors.accent),
      ExtTreeState.done => (Icons.check_circle_rounded, SemColors.success),
      ExtTreeState.skipped => (Icons.offline_pin_rounded, SemColors.textMuted),
      ExtTreeState.failed => (Icons.error_rounded, SemColors.danger),
    };
    final suffix = switch (row.state) {
      ExtTreeState.pending => '待安装',
      ExtTreeState.downloading => '下载中…',
      ExtTreeState.done => '已安装',
      ExtTreeState.skipped => '已安装（跳过）',
      ExtTreeState.failed => '失败',
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 4, 0, 4),
      child: Row(
        children: [
          if (row.depth > 0)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 14,
                color: SemColors.textMuted,
              ),
            ),
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              row.node.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (row.node.isDependency)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Capsule('依赖', color: SemColors.textMuted),
            ),
          Text(suffix, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}
