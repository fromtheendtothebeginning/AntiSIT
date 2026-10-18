import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'bundle_import.dart';
import 'ext_bridge.dart';
import 'ext_icon.dart';
import 'ext_open.dart';
import 'extension_item.dart';
import 'extension_store.dart';
import 'market/market_source.dart';
import 'market/market_view.dart';

/// 「拓展」页：网页形态的小功能，用户自己加进来。
///
/// 两个标签：**我的**（自己加的与装进来的）与**市场**（[MarketView]，从插件市场装）。
/// 自己加有三种加法：**填写网址**、**导入压缩包**（html/js/css 三件套，导入后解压成
/// 一份自包含页面）、**导入 JSON**；发行方还能在源码里放编译前固定的内置拓展
/// （见 [kBuiltinExtensions]，用户端只读）。
///
/// 加进来的每一条以卡片呈现：图标默认取网站 favicon（可自己改成图片网址或 emoji）、
/// 名称下方是简介、再下面是网址。右上角一个总开关能一下子隐藏**全部**网址
/// （卡片上那一行直接不显示；编辑 / 详情里始终看得到）。
/// 点开就是对应网页，网页里带着 [ExtBridge] 那套接口。
class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({super.key});

  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  ExtensionStore get _store => ExtensionStore.I;

  /// 0 = 我的，1 = 市场。
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
    if (!_store.loaded) unawaited(_store.load());
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
  }

  // ==================== 打开 ====================

  Future<void> _open(ExtensionItem e) => openExtension(context, e, onMessage: _toast);

  // ==================== 添加 ====================

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _addMenu() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('填写网址'),
              subtitle: const Text('给它起个名字，填一个 http(s) 网址', style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'url'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('导入压缩包'),
              subtitle: const Text('html / js / css 打成 zip；导入后自动解压',
                  style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'zip'),
            ),
            ListTile(
              leading: const Icon(Icons.data_object_rounded),
              title: const Text('导入 JSON'),
              subtitle: const Text('粘贴一份拓展 JSON（单条或数组）', style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'json'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (pick) {
      case 'url':
        await _edit();
      case 'zip':
        await _importBundle();
      case 'json':
        await _importJson();
    }
  }

  /// 填写网址 / 编辑 / 看详情：同一个弹窗；[isNew] 决定按钮与写盘方式。
  Future<void> _edit({ExtensionItem? item, bool isNew = true, bool readOnly = false}) async {
    final out = await showDialog<ExtensionItem>(
      context: context,
      builder: (_) => _AddEditDialog(item: item, isNew: isNew, readOnly: readOnly),
    );
    if (out == null) return;
    if (isNew) {
      await _store.add(out);
      _toast('已添加「${out.name}」');
    } else {
      await _store.update(out);
      _toast('已保存');
    }
  }

  /// 导入压缩包：选 zip → 解压到本地 → 让用户确认名称/简介/图标 → 入列。
  Future<void> _importBundle() async {
    XFile? picked;
    try {
      picked = await openFile(acceptedTypeGroups: [
        const XTypeGroup(label: '拓展压缩包', extensions: ['zip']),
      ]);
    } catch (e) {
      _toast('打开文件选择器失败：$e');
      return;
    }
    if (picked == null) return;

    final id = ExtensionItem.newId();
    ExtBundle bundle;
    try {
      bundle = extractBundle(bytes: await picked.readAsBytes(), dir: await _store.bundleDir(id));
    } on FormatException catch (e) {
      _toast(e.message);
      return;
    } catch (e) {
      _toast('解压失败：$e');
      return;
    }
    if (!mounted) return;

    // 预设好名称（压缩包名去掉扩展名）与入口，用户再补简介 / 图标
    final preset = ExtensionItem(
      id: id,
      name: _bundleName(picked.name),
      url: bundle.entry,
      bundled: true,
    );
    final item = await showDialog<ExtensionItem>(
      context: context,
      builder: (_) => _AddEditDialog(item: preset, isNew: true),
    );
    if (item == null) {
      await _store.remove(id); // 用户取消了：把刚解压出来的目录一并清掉
      return;
    }
    await _store.add(item);
    _toast('已导入「${item.name}」');
  }

  static String _bundleName(String fileName) {
    final base = fileName.split(RegExp(r'[/\\]')).last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  /// 导入 JSON：粘贴一份拓展 JSON（单条或数组），全部校验通过才入列。
  Future<void> _importJson() async {
    final list = await showDialog<List<ExtensionItem>>(
        context: context, builder: (_) => const _ImportDialog());
    if (list == null || !mounted) return;
    for (final item in list) {
      await _store.add(item);
    }
    _toast('已导入 ${list.length} 个拓展');
  }

  // ==================== 单条菜单 ====================

  Future<void> _itemMenu(ExtensionItem e) async {
    final builtin = _store.isBuiltin(e.id);
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('详情'),
              subtitle: Text(builtin ? '内置拓展：随 App 发布，不能改' : '看完整信息',
                  style: const TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'detail'),
            ),
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
    if (!mounted) return;
    switch (pick) {
      case 'detail':
        await _edit(item: e, isNew: false, readOnly: true);
      case 'edit':
        await _edit(item: e, isNew: false);
      case 'delete':
        if (!await confirmRemoveExtension(context, e)) return;
        await _store.remove(e.id);
        _toast('已删除「${e.name}」');
    }
  }

  // ==================== 界面 ====================

  /// 隐藏全部网址的总开关（卡片上那一行直接不显示，详情里照旧能看到）。
  /// 藏在标题栏是因为它管的是「整页要不要露网址」，摆在页面上会一直占位置。
  Future<void> _toggleHideUrls() => _store.setHideUrls(!_store.hideUrls);

  @override
  Widget build(BuildContext context) {
    final items = _store.items;
    final hide = _store.hideUrls;
    final market = _tab == 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('拓展'),
        actions: market
            ? [
                IconButton(
                  tooltip: '重新拉市场目录',
                  onPressed: () => unawaited(MarketSource.I.load(force: true)),
                  icon: const Icon(Icons.refresh),
                ),
              ]
            : [
                IconButton(
                  tooltip: hide ? '显示全部网址' : '隐藏全部网址',
                  onPressed: items.isEmpty ? null : _toggleHideUrls,
                  // 开着时用强调色 + 闭眼图标，一眼看得出当前状态
                  color: hide ? SemColors.accent : null,
                  icon: Icon(hide ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                ),
                IconButton(tooltip: '添加拓展', onPressed: _addMenu, icon: const Icon(Icons.add)),
              ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: GlassTabs(
              labels: const ['我的', '市场'],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          Expanded(
            child: market
                ? MarketView(onInstalled: _toast)
                : (items.isEmpty ? _empty() : _grid(items)),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AppCard(
              child: Column(
                children: [
                  Icon(Icons.extension_outlined, size: 40, color: SemColors.textMuted),
                  const SizedBox(height: 12),
                  const Text('还没有拓展',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    '拓展是网页形态的小功能：填一个网址、导入一份 html/js/css 压缩包，'
                    '或粘贴一份拓展 JSON 都行。加进来就会以卡片出现在这里，点开即用。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: SemColors.textMuted, height: 1.7),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.tonal(
                          onPressed: () => setState(() => _tab = 1), child: const Text('去市场看看')),
                      OutlinedButton(onPressed: () => _edit(), child: const Text('填写网址')),
                      OutlinedButton(onPressed: _importBundle, child: const Text('导入压缩包')),
                      OutlinedButton(onPressed: _importJson, child: const Text('导入 JSON')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '打开的网页带着 antiSIT 接口：读 App 配色、用自己的本地存储、弹提示、关页面。'
                    'App 里的用户数据（学号 / 课表 / 成绩）不会给出去。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: SemColors.textMuted, height: 1.7),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _grid(List<ExtensionItem> items) => GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.16,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          for (final e in items) _card(e),
          _addCard(),
        ],
      );

  Widget _card(ExtensionItem e) => AppCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        onTap: () => _open(e),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExtIcon(item: e),
                const Spacer(),
                if (e.builtin)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Capsule('内置', color: SemColors.textMuted),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: e.builtin ? '详情' : '编辑 / 删除',
                  onPressed: () => _itemMenu(e),
                  icon: Icon(Icons.more_horiz, size: 18, color: SemColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(e.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            if (e.desc.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(e.desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, height: 1.4, color: SemColors.textSecondary)),
            ],
            const Spacer(),
            if (!_store.hideUrls)
              Text(e.urlLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
          ],
        ),
      );

  Widget _addCard() => AppCard(
        padding: const EdgeInsets.all(14),
        onTap: _addMenu,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, size: 26, color: SemColors.textMuted),
            const SizedBox(height: 8),
            Text('添加拓展',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: SemColors.textSecondary)),
          ],
        ),
      );
}

/// 添加 / 编辑 / 详情弹窗：输入控制器归它的 State 管——弹窗退场动画期间控件还在
/// 重建，在外面 await 完就 dispose 会撞上「用了已释放的控制器」。
/// [readOnly] = 内置拓展的详情（只看不改）。校验通过就把 [ExtensionItem] 返回。
class _AddEditDialog extends StatefulWidget {
  const _AddEditDialog({this.item, required this.isNew, this.readOnly = false});

  final ExtensionItem? item;
  final bool isNew;
  final bool readOnly;

  @override
  State<_AddEditDialog> createState() => _AddEditDialogState();
}

class _AddEditDialogState extends State<_AddEditDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.item?.name ?? '');
  late final TextEditingController _url =
      TextEditingController(text: widget.item?.bundled == true ? '' : widget.item?.url ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.item?.desc ?? '');
  late final TextEditingController _icon = TextEditingController(text: widget.item?.icon ?? '');
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
    final url = _bundled ? widget.item!.url : ExtensionItem.normalizeUrl(_url.text);
    if (url == null) {
      setState(() => _error = '网址要能打开：填完整域名（没写协议会按 https 补）');
      return;
    }
    final name = _name.text.trim();
    final desc = _desc.text.trim();
    final icon = _icon.text.trim();
    // 编辑既有条目一律走 copyWith：市场字段（版本 / 哈希 / 权限 / 来源）不能因为
    // 「在 App 里改了个名字」就丢掉——丢了既看不到更新，权限门也会跟着失效。
    final base = widget.item ??
        ExtensionItem(id: ExtensionItem.newId(), name: '', url: url, bundled: _bundled);
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
      title: Text(ro
          ? '拓展详情'
          : widget.isNew
              ? '添加拓展'
              : '编辑拓展'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ro)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                    _bundled
                        ? '内置 / 本地拓展：入口是一个本地文件'
                        : '内置拓展：随 App 发布，不能在这里改',
                    style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
              ),
            TextField(
              controller: _name,
              enabled: !ro,
              autofocus: !ro,
              decoration: const InputDecoration(labelText: '名称', hintText: '例如：课程表工具'),
            ),
            const SizedBox(height: 10),
            if (_bundled)
              // 压缩包导入的：入口是解压出来的本地文件，改它没意义
              TextField(
                enabled: false,
                controller: TextEditingController(text: widget.item!.url),
                decoration: const InputDecoration(
                    labelText: '入口文件', helperText: '导入压缩包解压出来的 index.html'),
              )
            else
              TextField(
                controller: _url,
                enabled: !ro,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                    labelText: '网址', hintText: 'https://example.com/app'),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _desc,
              enabled: !ro,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: '简介（可空）', hintText: '一句话说明它做什么，显示在卡片名称下方'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _icon,
              enabled: !ro,
              decoration: const InputDecoration(
                  labelText: '图标（可空）', hintText: '图片网址或 emoji；留空用网站 favicon'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!,
                  style: TextStyle(fontSize: 12, color: SemColors.danger, height: 1.5)),
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
class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
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
              const Text('粘贴拓展 JSON（单条或数组，字段 name / url / desc / icon）：',
                  style: TextStyle(fontSize: 12.5)),
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
                Text(_error!,
                    style: TextStyle(fontSize: 12, color: SemColors.danger, height: 1.5)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: _submit, child: const Text('导入')),
        ],
      );
}
