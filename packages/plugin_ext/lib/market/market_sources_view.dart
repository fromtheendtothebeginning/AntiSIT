import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'market_entry.dart';
import 'market_source.dart';
import 'market_sources.dart';

/// 第三方源的界面零件：「源」面板、添加源、添加前确认指纹。
///
/// 抽出来是因为 market_view.dart 已经够长了，而且这三块跟「浏览/安装」是两回事。
/// 用法的重点是**指纹**：目录里的公钥是源自报的，App 只能保证「加进来之后不被换」，
/// 「第一次这个源是不是作者的」只能靠用户拿指纹和作者公布的那串对照。
Future<void> showSourceSheet(
  BuildContext context, {
  void Function(String message)? onMessage,
}) async {
  final official = MarketSource.I;
  final sources = ExtSourceStore.I;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('插件源',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                '官方目录由 AntiSIT 维护、发布时签名，公钥内置在 App 里。第三方源是别人在自己'
                '仓库里发的，内容没经过审核——收录 ≠ 背书，装之前自己掂量。',
                style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6),
              ),
              const SizedBox(height: 14),
              _tile(
                title: '官方目录',
                fingerprint: '公钥内置在 App 里',
                subtitle: official.ready
                    ? '${official.entries.length} 条 · '
                        '${official.fromCache ? '用的缓存' : (official.activeBase.isEmpty ? '已加载' : official.activeBase)}'
                    : (official.error.isEmpty ? '还没拉到' : official.error),
              ),
              for (final src in sources.sources)
                _tile(
                  title: src.label,
                  fingerprint: '公钥指纹 ${src.fingerprint}',
                  subtitle: sources.errorsBySource.containsKey(src.id)
                      ? sources.errorsBySource[src.id]!
                      : '${(sources.entriesBySource[src.id] ?? const []).length} 条 · ${src.base}',
                  onRemove: () async {
                    Navigator.pop(sheetCtx);
                    final ok = await confirmRemoveSource(context, src);
                    if (ok == true) {
                      await sources.remove(src.id);
                      onMessage?.call('已移除源「${src.label}」');
                    }
                  },
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        addSourceFlow(context, onMessage: onMessage);
                      },
                      child: const Text('添加第三方源'),
                    ),
                  ),
                  if (sources.sources.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => sources.refresh().then((_) => setSheet(() {})),
                      child: const Text('刷新'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 输入地址 → 拉取预览 → 指纹确认 → 添加。失败时把原因交给 [onMessage]。
Future<void> addSourceFlow(
  BuildContext context, {
  void Function(String message)? onMessage,
}) async {
  final sources = ExtSourceStore.I;
  final input = await showAddSourceDialog(context);
  if (input == null || input.isEmpty) return;
  if (!context.mounted) return;

  try {
    final preview = await sources.preview(input);
    if (!context.mounted) return;
    final ok = await confirmSourceDialog(context, preview.draft, preview.entries);
    if (ok == true) {
      await sources.add(preview.draft, preview.entries);
      onMessage?.call('已添加源「${preview.draft.label}」');
    }
  } catch (err) {
    onMessage?.call('$err'.replaceFirst('Bad state: ', ''));
  }
}

Widget _tile({
  required String title,
  required String subtitle,
  required String fingerprint,
  Future<void> Function()? onRemove,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(fingerprint,
                    style: TextStyle(fontSize: 11.5, color: SemColors.accent, height: 1.4)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(fontSize: 11, color: SemColors.textMuted, height: 1.5)),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: '移除这个源',
              visualDensity: VisualDensity.compact,
              onPressed: () => onRemove(),
              icon: Icon(Icons.delete_outline, size: 18, color: SemColors.textMuted),
            ),
        ],
      ),
    );

/// 输入源地址（`所有者/仓库` 或一个 https 地址）。
Future<String?> showAddSourceDialog(BuildContext context) => showDialog<String>(
      context: context,
      builder: (_) => const _AddSourceDialog(),
    );

class _AddSourceDialog extends StatefulWidget {
  const _AddSourceDialog();

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _input.text.trim();
    if (v.isEmpty) {
      setState(() => _error = '填一个源地址');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('添加第三方源'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('填作者的仓库（`所有者/仓库`），或作者给的 https 地址：',
                  style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 10),
              TextField(
                controller: _input,
                autofocus: true,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: '源地址',
                  hintText: '例如 someone/antisit-plugins',
                ),
              ),
              const SizedBox(height: 8),
              Text('作者会在他的 README 或分享里给出这个地址和**公钥指纹**，'
                  '下一步会让您核对指纹。',
                  style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6)),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(fontSize: 12, color: SemColors.danger, height: 1.5)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: _submit, child: const Text('下一步')),
        ],
      );
}

/// 移除源之前的确认。
Future<bool?> confirmRemoveSource(BuildContext context, ExtSource src) => showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('移除源「${src.label}」？'),
        content: const Text('只是不再从它这儿列插件；已经装好的拓展不受影响，要删去「我的」里删。',
            style: TextStyle(fontSize: 13, height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('移除')),
        ],
      ),
    );

/// 添加源之前把**指纹**摆出来——这是这套「第三方源」唯一的信任来源。
Future<bool?> confirmSourceDialog(
  BuildContext context,
  ExtSource src,
  List<MarketEntry> entries,
) =>
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('添加源「${src.label}」？'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('公钥指纹', style: TextStyle(fontSize: 11.5, color: SemColors.textMuted)),
              const SizedBox(height: 2),
              Text(src.fingerprint,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                      color: SemColors.accent)),
              const SizedBox(height: 8),
              Text(
                '和作者公布的那串对照一致再添加。加进来之后，这个源换钥匙（或有人在中间替换）'
                '会被自动停用；但「第一次」只能靠你自己核对。',
                style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6),
              ),
              const SizedBox(height: 12),
              _kv('地址', src.base),
              _kv(
                  '条目',
                  '${entries.length} 条：'
                      '${entries.take(4).map((e) => e.name).join('、')}${entries.length > 4 ? '…' : ''}'),
              const SizedBox(height: 10),
              Text('第三方源的内容没有经过官方审核。',
                  style: TextStyle(fontSize: 11.5, color: SemColors.danger, height: 1.6)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('指纹一致，添加')),
        ],
      ),
    );

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 40,
              child: Text(k, style: TextStyle(fontSize: 12, color: SemColors.textMuted))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5, height: 1.5))),
        ],
      ),
    );
