import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:campus_core/campus_core.dart';

import '../extension_item.dart';
import '../ext_icon.dart';
import '../ext_open.dart';
import '../ext_permissions.dart';
import 'market_entry.dart';
import 'market_installer.dart';
import 'market_source.dart';

/// 「插件市场」页（拓展页里的第二个标签）：
/// 列出市场目录里的拓展，装 / 更新 / 打开 / 卸载。
///
/// 目录必须**验签**通过才显示（见 [MarketSource]），装的时候还要对 sha256；
/// 市场装的拓展按清单声明的权限放行（见 `ExtBridge`），安装弹窗把权限摊给用户看。
class MarketView extends StatefulWidget {
  const MarketView({super.key, this.onInstalled});

  /// 装完 / 更新完说一句（拓展页拿它弹提示）。
  final void Function(String message)? onInstalled;

  @override
  State<MarketView> createState() => _MarketViewState();
}

class _MarketViewState extends State<MarketView> {
  final _search = TextEditingController();
  String _category = '全部';
  String _appVersion = '';
  bool _busy = false;

  MarketSource get _source => MarketSource.I;

  @override
  void initState() {
    super.initState();
    _source.addListener(_onChanged);
    if (_source.status == MarketStatus.idle) unawaited(_source.load());
    unawaited(_readAppVersion());
  }

  @override
  void dispose() {
    _source.removeListener(_onChanged);
    _search.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// 本机版本号：判「需要升级 App」。读不到就当没要求（软门，不挡人）。
  Future<void> _readAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version);
    } catch (_) {
      // 测试环境 / 平台拿不到：不设门
    }
  }

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ==================== 过滤 ====================

  List<MarketEntry> get _visible {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final e in _source.entries)
        if ((_category == '全部' || e.category == _category) &&
            (q.isEmpty ||
                e.name.toLowerCase().contains(q) ||
                e.desc.toLowerCase().contains(q) ||
                e.author.toLowerCase().contains(q) ||
                e.id.toLowerCase().contains(q)))
          e,
    ];
  }

  List<String> get _categories {
    final have = {for (final e in _source.entries) e.category};
    return [
      '全部',
      for (final c in ['学习', '工具', '生活', '娱乐', '其他'])
        if (have.contains(c)) c,
    ];
  }

  // ==================== 安装 / 更新 / 卸载 ====================

  Future<void> _install(MarketEntry e) async {
    final installer = MarketInstaller();
    final update = installer.hasUpdate(e);
    final ok = await _confirmInstall(e, update: update);
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await installer.install(e);
      widget.onInstalled?.call(update ? '已更新「${e.name}」' : '已安装「${e.name}」');
    } catch (err) {
      _say('装不上：${_short(err)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uninstall(MarketEntry e) async {
    final item = MarketInstaller().installed(e.id);
    if (item == null) return;
    if (!await confirmRemoveExtension(context, item)) return;
    await MarketInstaller().uninstall(e.id);
    widget.onInstalled?.call('已卸载「${e.name}」');
  }

  Future<void> _open(MarketEntry e) async {
    final item = MarketInstaller().installed(e.id);
    if (item == null) return;
    await openExtension(context, item, onMessage: _say);
  }

  /// 装之前把来源 / 版本 / 大小 / 权限摊开说清楚。
  Future<bool?> _confirmInstall(MarketEntry e, {required bool update}) {
    final perms = describeSensitivePermissions(e.permissions);
    final installed = update ? MarketInstaller().installed(e.id) : null;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(update ? '更新「${e.name}」？' : '安装「${e.name}」？'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('来源', '插件市场 · ${e.author.isEmpty ? '佚名' : e.author}'),
              if (e.version.isNotEmpty) _kv('版本', update ? '${installed?.version} → ${e.version}' : e.version),
              if (e.isBundle && e.size > 0) _kv('大小', _size(e.size)),
              _kv('分类', e.category),
              if (e.desc.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(e.desc, style: const TextStyle(fontSize: 12.5, height: 1.6)),
              ],
              const SizedBox(height: 12),
              Text('它要用的接口', style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
              const SizedBox(height: 6),
              if (perms.isEmpty)
                Text('只是读配色、弹提示、改自己的卡片这类界面接口。',
                    style: TextStyle(fontSize: 12, color: SemColors.textSecondary, height: 1.6))
              else
                for (final p in perms)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('· $p',
                        style: TextStyle(fontSize: 12, color: SemColors.textSecondary, height: 1.5)),
                  ),
              const SizedBox(height: 10),
              Text(
                e.isBundle
                    ? (update
                        ? '更新只换页面内容，拓展里存的数据（设置、历史）留着。'
                        : '内容来自插件市场，已过签名与哈希校验；装好后随时能卸载。')
                    : '网址型：打开的是第三方网站，内容由站点控制、随时可能变化，'
                        'App 只保证「这个地址是市场登记的」。',
                style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(update ? '更新' : '安装')),
        ],
      ),
    );
  }

  // ==================== 界面 ====================

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _source.load(force: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _top()),
              if (_source.status == MarketStatus.ready)
                _visible.isEmpty
                    ? SliverToBoxAdapter(child: _empty())
                    : SliverList.builder(
                        itemCount: _visible.length,
                        itemBuilder: (_, i) => _card(_visible[i]),
                      )
              else
                const SliverToBoxAdapter(child: SizedBox(height: 0)),
            ],
          ),
        ),
        if (_source.status == MarketStatus.loading)
          const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
        if (_busy)
          Container(
            color: Colors.black.withValues(alpha: 0.18),
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _top() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: '搜名称 / 简介 / 作者',
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
            if (_categories.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final c in _categories)
                    GestureDetector(
                      onTap: () => setState(() => _category = c),
                      child: Capsule(
                        c,
                        color: _category == c ? SemColors.accent : SemColors.textMuted,
                        soft: _category == c ? null : SemColors.textMuted.withValues(alpha: 0.08),
                      ),
                    ),
                ],
              ),
            ],
            if (_source.status == MarketStatus.failed) _errorBox(),
            if (_source.status == MarketStatus.ready && _source.fromCache)
              _noteBox('网络没通，用的是上次缓存的目录（${_when(_source.fetchedAt)}）'),
            const SizedBox(height: 6),
          ],
        ),
      );

  Widget _errorBox() => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('市场目录用不了',
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.bold, color: SemColors.danger)),
              const SizedBox(height: 6),
              Text(_source.error,
                  style: TextStyle(fontSize: 12, color: SemColors.textSecondary, height: 1.6)),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                    onPressed: () => _source.load(force: true), child: const Text('重试')),
              ),
            ],
          ),
        ),
      );

  Widget _noteBox(String text) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(text,
            style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6)),
      );

  Widget _empty() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 24),
        child: Center(
          child: Text(
            _source.entries.isEmpty
                ? '市场里还没有拓展。想放一个上来？看市场仓库的投稿说明。'
                : '没找到符合条件的拓展。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: SemColors.textMuted, height: 1.7),
          ),
        ),
      );

  Widget _card(MarketEntry e) {
    final installer = MarketInstaller();
    final installed = installer.installed(e.id);
    final update = installer.hasUpdate(e);
    final needsApp = _appVersion.isNotEmpty && e.needsNewerApp(_appVersion);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        onTap: installed != null ? () => _open(e) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExtIcon(item: _asItem(e)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(e.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                          if (e.version.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text('v${e.version}',
                                style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                          ],
                          if (update) ...[
                            const SizedBox(width: 6),
                            Capsule('有新版', color: SemColors.accent),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(e.desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, height: 1.45, color: SemColors.textSecondary)),
                      const SizedBox(height: 5),
                      Text(
                        [
                          if (e.author.isNotEmpty) e.author,
                          e.category,
                          if (!e.isBundle) '网址',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: SemColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (needsApp)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('需要升级 App（≥${e.minAppVersion}）',
                        style: TextStyle(fontSize: 11.5, color: SemColors.danger)),
                  ),
                if (installed != null && !update)
                  IconButton(
                    tooltip: '卸载',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _uninstall(e),
                    icon: Icon(Icons.delete_outline, size: 18, color: SemColors.textMuted),
                  ),
                if (installed != null && !update)
                  const SizedBox(width: 6),
                if (installed != null && !update)
                  OutlinedButton(onPressed: () => _open(e), child: const Text('打开'))
                else if (needsApp)
                  const FilledButton(onPressed: null, child: Text('装不了'))
                else
                  FilledButton(
                    onPressed: _busy ? null : () => _install(e),
                    child: Text(update ? '更新' : '安装'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 市场条目画成卡片图标要的样子（本地包没有 favicon 可抓，所以 bundled 留空：
  /// 图标走 emoji / 图片网址 / 名称首字）。
  static ExtensionItem _asItem(MarketEntry e) => ExtensionItem(
        id: e.id,
        name: e.name,
        url: e.url,
        icon: e.icon,
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Text(k, style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(fontSize: 12.5, height: 1.5)),
            ),
          ],
        ),
      );

  static String _size(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
          ? '${(bytes / 1024).toStringAsFixed(1)} KB'
          : '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';

  static String _when(DateTime? t) {
    if (t == null) return '时间未知';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    return '${d.inDays} 天前';
  }

  static String _short(Object e) {
    final s = '$e'.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}
