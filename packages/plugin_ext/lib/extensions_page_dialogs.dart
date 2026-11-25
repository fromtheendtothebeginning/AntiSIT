import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'extension_item.dart';

/// 单条拓展的操作菜单：返回用户选的项（detail / consent / edit / delete / demo-downgrade）。
Future<String?> showExtensionItemMenu(
  BuildContext context,
  ExtensionItem e, {
  required bool builtin,
  required bool demo,
}) =>
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('详情'),
              subtitle: Text(
                builtin ? '内置拓展：随 App 发布，不能改' : '看完整信息',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 'detail'),
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('权限'),
              subtitle: const Text(
                '静态权限 + 运行时授权',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 'consent'),
            ),
            if (demo && e.id == 'demo-note') ...[
              ListTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: const Text('降级到 v1.0.0（重测演示）'),
                subtitle: const Text('把这条假拓展降回旧版，重走「可更新 → 跳市场」流程',
                    style: TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, 'demo-downgrade'),
              ),
            ],
            if (!builtin) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              ListTile(
                leading: Icon(Icons.link_off_rounded, color: SemColors.danger),
                title: Text('删除', style: TextStyle(color: SemColors.danger)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ],
        ),
      ),
    );

/// 添加 / 编辑 / 详情弹窗：输入控制器归它的 State 管——弹窗退场动画期间控件还在
/// 重建，在外面 await 完就 dispose 会撞上「用了已释放的控制器」。
class ExtensionEditDialog extends StatefulWidget {
  const ExtensionEditDialog({
    super.key,
    this.item,
    required this.isNew,
    this.readOnly = false,
  });

  final ExtensionItem? item;
  final bool isNew;

  /// 内置拓展的详情（只看不改）。
  final bool readOnly;

  @override
  State<ExtensionEditDialog> createState() => _ExtensionEditDialogState();
}

class _ExtensionEditDialogState extends State<ExtensionEditDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.item?.name ?? '',
  );
  late final TextEditingController _url = TextEditingController(
    text: widget.item?.bundled == true ? '' : widget.item?.url ?? '',
  );
  late final TextEditingController _desc = TextEditingController(
    text: widget.item?.desc ?? '',
  );
  late final TextEditingController _icon = TextEditingController(
    text: widget.item?.icon ?? '',
  );
  String? _error;

  bool get _bundled => widget.item?.bundled == true;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _desc.dispose();
    _icon.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _bundled
        ? widget.item!.url
        : ExtensionItem.normalizeUrl(_url.text);
    if (url == null) {
      setState(() => _error = '网址要能打开：填完整域名（没写协议会按 https 补）');
      return;
    }
    final name = _name.text.trim();
    final desc = _desc.text.trim();
    final icon = _icon.text.trim();
    // 编辑既有条目一律走 copyWith：市场字段（版本 / 哈希 / 权限 / 来源）不能丢，
    // 丢了既看不到更新，权限门也会跟着失效。
    final base =
        widget.item ??
        ExtensionItem(
          id: ExtensionItem.newId(),
          name: '',
          url: url,
          bundled: _bundled,
        );
    Navigator.pop(
      context,
      base.copyWith(
        name: name.isEmpty
            ? (base.name.isNotEmpty
                  ? base.name
                  : (_bundled ? '本地拓展' : Uri.parse(url).host))
            : name,
        url: url,
        desc: desc,
        icon: icon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ro = widget.readOnly;
    return AlertDialog(
      title: Text(
        ro
            ? '拓展详情'
            : widget.isNew
            ? '添加拓展'
            : '编辑拓展',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ro)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _bundled ? '内置 / 本地拓展：入口是一个本地文件' : '内置拓展：随 App 发布，不能在这里改',
                  style: TextStyle(fontSize: 12, color: SemColors.textMuted),
                ),
              ),
            TextField(
              controller: _name,
              enabled: !ro,
              autofocus: !ro,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如：课程表工具',
              ),
            ),
            const SizedBox(height: 10),
            if (_bundled)
              // 压缩包导入的：入口是解压出来的本地文件，改它没意义
              TextField(
                enabled: false,
                controller: TextEditingController(text: widget.item!.url),
                decoration: const InputDecoration(
                  labelText: '入口文件',
                  helperText: '导入压缩包解压出来的 index.html',
                ),
              )
            else
              TextField(
                controller: _url,
                enabled: !ro,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '网址',
                  hintText: 'https://example.com/app',
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _desc,
              enabled: !ro,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '简介（可空）',
                hintText: '一句话说明它做什么，显示在卡片名称下方',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _icon,
              enabled: !ro,
              decoration: const InputDecoration(
                labelText: '图标（可空）',
                hintText: 'line:handyman / 图片网址 / emoji；留空用网站 favicon',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 12,
                  color: SemColors.danger,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ro ? '关闭' : '取消'),
        ),
        if (!ro)
          FilledButton(
            onPressed: _submit,
            child: Text(widget.isNew ? '添加' : '保存'),
          ),
      ],
    );
  }
}

/// 导入弹窗：粘贴一份拓展 JSON（单条或数组），解析通过就把整批返回给调用方。
Future<List<ExtensionItem>?> showExtensionImportDialog(BuildContext context) =>
    showDialog<List<ExtensionItem>>(
      context: context,
      builder: (_) => const ExtensionImportDialog(),
    );

/// 粘贴一份拓展 JSON（单条或数组），解析通过就把整批返回给调用方。
class ExtensionImportDialog extends StatefulWidget {
  const ExtensionImportDialog({super.key});

  @override
  State<ExtensionImportDialog> createState() => _ExtensionImportDialogState();
}

class _ExtensionImportDialogState extends State<ExtensionImportDialog> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      Navigator.pop(context, ExtensionItem.parseImported(_text.text));
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('导入拓展'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '粘贴拓展 JSON（单条或数组，字段 name / url / desc / icon）：',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _text,
            maxLines: 6,
            autofocus: true,
            style: const TextStyle(fontSize: 12, height: 1.5),
            decoration: const InputDecoration(
              hintText: '[{"name": "我的拓展", "url": "https://example.com"}]',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                fontSize: 12,
                color: SemColors.danger,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('导入')),
    ],
  );
}

/// 下载失败：把异常包一层再从进度框带回来（失败和结果走同一个返回值）。
class ExtensionDownloadFailure {
  const ExtensionDownloadFailure(this.error);

  final Object error;
}

/// 不可取消的下载进度框：任务完成 / 失败时自己关掉，并把结果交给调用方。
class ExtensionDownloadDialog<T> extends StatefulWidget {
  const ExtensionDownloadDialog({
    super.key,
    required this.label,
    required this.task,
  });

  final String label;
  final Future<T> Function() task;

  @override
  State<ExtensionDownloadDialog<T>> createState() =>
      _ExtensionDownloadDialogState<T>();
}

class _ExtensionDownloadDialogState<T> extends State<ExtensionDownloadDialog<T>> {
  @override
  void initState() {
    super.initState();
    Future<T>.microtask(widget.task)
        .then((value) {
          if (mounted) Navigator.of(context).pop<Object?>(value);
        })
        .catchError((Object e, StackTrace _) {
          if (mounted) Navigator.of(context).pop<Object?>(ExtensionDownloadFailure(e));
        });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(widget.label, style: const TextStyle(fontSize: 13.5)),
          ),
        ],
      ),
    ),
  );
}
