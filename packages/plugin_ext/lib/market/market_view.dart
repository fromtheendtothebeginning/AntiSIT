import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import '../extension_item.dart';
import '../ext_open.dart';
import 'ext_dependency_plan.dart';
import 'ext_dependency_sheet.dart';
import 'market_entry.dart';
import 'market_installer.dart';
import 'market_source.dart';
import 'market_sources.dart';
import 'market_sources_view.dart';
import 'market_view_tiles.dart';

/// 「插件市场」页：列出市场目录里的拓展，装 / 更新 / 打开 / 卸载。
///
/// 目录必须验签通过才显示，安装时再校 sha256；市场拓展按清单声明的权限放行，
/// 安装弹窗把敏感权限摊给用户看。
class MarketView extends StatefulWidget {
  const MarketView({super.key, this.onInstalled, this.focusId, this.topPadding = 0});

  /// 装完 / 更新完说一句（拓展页拿它弹提示）。
  final void Function(String message)? onInstalled;

  /// 要定位的拓展 id：从拓展页「可更新」卡片跳进来时带上，目录就绪后自动过滤到它。
  final String? focusId;

  /// 列表顶部额外留白：市场页是悬浮玻璃顶栏，留白放在滚动内容里才能滚穿顶栏。
  final double topPadding;

  @override
  State<MarketView> createState() => _MarketViewState();
}

class _MarketViewState extends State<MarketView> {
  final _search = TextEditingController();
  String _category = '全部';
  String _appVersion = '';
  bool _busy = false;
  bool _focusApplied = false;

  MarketSource get _source => MarketSource.I;

  /// 用户添加的第三方源（作者自己发的那种，见 market_sources.dart）。
  ExtSourceStore get _sources => ExtSourceStore.I;

  @override
  void initState() {
    super.initState();
    _source.addListener(_onChanged);
    _sources.addListener(_onChanged);
    if (_source.status == MarketStatus.idle) unawaited(_source.load());
    if (!_sources.loaded) unawaited(_sources.load());
    unawaited(_readAppVersion());
  }

  @override
  void dispose() {
    _source.removeListener(_onChanged);
    _sources.removeListener(_onChanged);
    _search.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// 定位只做一次：目录里找到目标后把搜索框设为它的名字，用户可随时清掉过滤。
  void _applyFocus() {
    if (_focusApplied || widget.focusId == null) return;
    for (final e in _all) {
      if (e.id == widget.focusId) {
        _focusApplied = true;
        _category = '全部';
        _search.text = e.name;
        return;
      }
    }
  }

  /// 本机版本号：读不到就当没要求（软门，不挡人）。
  Future<void> _readAppVersion() async {
    final v = await ExtensionItem.appVersionLoader();
    if (mounted && v.isNotEmpty) setState(() => _appVersion = v);
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

  /// 官方目录 + 所有第三方源（第三方排在后面，卡片上标来源）。
  List<MarketEntry> get _all => [..._source.entries, ..._sources.allEntries];

  List<MarketEntry> get _visible {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final e in _all)
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
    final have = {for (final e in _all) e.category};
    return [
      '全部',
      for (final c in ['学习', '工具', '生活', '娱乐', '其他'])
        if (have.contains(c)) c,
    ];
  }

  /// 所有已装且有新版的条目（官方 + 第三方源），不受当前搜索 / 分类过滤影响。
  /// 同一 id 由多个源提供时只认已装的那个源；需要更高版本 App 的不算进来。
  List<MarketEntry> get _updatable {
    final installer = MarketInstaller();
    final out = <String, MarketEntry>{};
    for (final e in _all) {
      if (!installer.hasUpdate(e)) continue;
      if (e.needsNewerApp(_appVersion)) continue;
      final have = installer.installed(e.id);
      if (have == null || e.sourceId != have.sourceId) continue;
      out.putIfAbsent(e.id, () => e);
    }
    return out.values.toList();
  }

  Future<void> _install(MarketEntry e) async {
    final installer = MarketInstaller();
    final update = installer.hasUpdate(e);
    // 依赖规划：应用插件要连带装好它声明的依赖插件（按拓扑顺序）
    final plan = installer.planFor(e, catalog: {for (final x in _all) x.id: x});
    final needsTree = plan.missing.length > 1 || plan.order.length > 1;
    if (plan.unresolved.isNotEmpty) {
      showErr(
        context,
        '「${e.name}」依赖的插件在市场里找不到：${plan.unresolved.join('、')}',
        title: '装不了',
      );
      return;
    }
    final ok = await showMarketInstallDialog(
      context,
      e,
      update: update,
      installedVersion: installer.installed(e.id)?.version,
      thirdPartyLabel: '${_sources.byId(e.sourceId)?.label ?? e.sourceId}'
          '${e.author.isEmpty ? '' : '（${e.author}）'}',
      dependencies: needsTree
          ? [for (final n in plan.missing.where((n) => n.id != e.id)) n.name]
          : const [],
    );
    if (ok != true) return;

    // 有依赖时走树状下载界面：按拓扑序先装依赖、再装应用插件
    if (needsTree && mounted) {
      final rows = extTreeRows(plan, installed: installer.installedVersions());
      var failures = <String>[];
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => ExtDependencyDownloadSheet(
          rows: rows,
          run: (onStep) async {
            final report = await installer.installPlan(plan, onStep: onStep);
            failures = report.failures;
          },
        ),
      );
      if (!mounted) return;
      if (failures.isEmpty) {
        widget.onInstalled?.call('已安装「${e.name}」及 ${plan.missing.length - 1} 个依赖');
      } else {
        widget.onInstalled?.call('部分插件没装成功（${failures.length} 个）');
      }
      return;
    }

    setState(() => _busy = true);
    try {
      await installer.install(e);
      widget.onInstalled?.call(update ? '已更新「${e.name}」' : '已安装「${e.name}」');
    } catch (err) {
      if (mounted) showErr(context, err, title: update ? '更新失败' : '安装失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 一次更新所有「已装且有新版」的条目：逐条下载校验，单条失败不挡后面的。
  Future<void> _updateAll() async {
    final targets = _updatable;
    if (targets.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更新全部拓展？'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('将依次更新 ${targets.length} 个拓展：',
                  style: const TextStyle(fontSize: 12.5, height: 1.6)),
              const SizedBox(height: 6),
              for (final e in targets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('· ${e.name}${e.version.isEmpty ? '' : ' → v${e.version}'}',
                      style: const TextStyle(fontSize: 12.5, height: 1.5)),
                ),
              const SizedBox(height: 10),
              Text(
                '更新只换页面内容，拓展里存的数据（设置、历史）保留；'
                '单个失败不会影响其他条目。',
                style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('更新')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    var done = 0;
    final failed = <String>[];
    try {
      for (final e in targets) {
        try {
          await MarketInstaller().install(e);
          done++;
        } catch (err) {
          failed.add('${e.name}：${shortMarketError(err)}');
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (failed.isEmpty) {
      widget.onInstalled?.call('已更新 $done 个拓展');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('部分拓展没更新成功'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('成功 $done 个，失败 ${failed.length} 个：',
                  style: const TextStyle(fontSize: 12.5, height: 1.6)),
              const SizedBox(height: 6),
              for (final line in failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('· $line',
                      style: const TextStyle(fontSize: 12, height: 1.6)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    _applyFocus();
    return Stack(
      children: [
        RefreshIndicator(
          // 刷新圈落在悬浮切换器下面，别贴着屏幕最上沿（issue #14）
          edgeOffset: widget.topPadding,
          onRefresh: () => _source.load(force: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _top()),
              // 官方目录拉不到时，第三方源照样要能列（一个源坏掉不该带崩整页）
              if (_visible.isNotEmpty)
                SliverList.builder(
                  itemCount: _visible.length,
                  itemBuilder: (_, i) {
                    final e = _visible[i];
                    final installer = MarketInstaller();
                    return MarketEntryCard(
                      entry: e,
                      installed: installer.installed(e.id),
                      update: installer.hasUpdate(e),
                      needsApp: e.needsNewerApp(_appVersion),
                      focused: e.id == widget.focusId,
                      busy: _busy,
                      onOpen: () => _open(e),
                      onInstall: () => _install(e),
                      onUninstall: () => _uninstall(e),
                    );
                  },
                )
              else if (_source.status == MarketStatus.ready)
                SliverToBoxAdapter(
                    child: MarketEmpty(catalogEmpty: _source.entries.isEmpty))
              else
                const SliverToBoxAdapter(child: SizedBox(height: 0)),
              // 底栏是玻璃浮层：列表底部让出底栏这一截，最后一条才不会被压住
              SliverToBoxAdapter(
                  child: SizedBox(height: MediaQuery.paddingOf(context).bottom)),
            ],
          ),
        ),
        if (_source.status == MarketStatus.loading)
          Positioned(
            top: widget.topPadding,
            left: 0,
            right: 0,
            child: const LinearProgressIndicator(minHeight: 2),
          ),
        if (_busy)
          Container(
            color: Colors.black.withValues(alpha: 0.18),
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _top() => Padding(
        padding: EdgeInsets.fromLTRB(12, 8 + widget.topPadding, 12, 4),
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
            if (_updatable.isNotEmpty) ...[
              const SizedBox(height: 8),
              MarketUpdateBanner(
                count: _updatable.length,
                busy: _busy,
                onUpdateAll: _updateAll,
              ),
            ],
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
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => showSourceSheet(context, onMessage: _say),
                  icon: const Icon(Icons.dns_outlined, size: 16),
                  label: Text(
                    _sources.sources.isEmpty
                        ? '插件源：只有官方目录'
                        : '插件源：官方 + ${_sources.sources.length} 个第三方',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const Spacer(),
                if (_sources.sources.isNotEmpty)
                  TextButton(
                    onPressed: _sources.refreshing ? null : () => unawaited(_sources.refresh()),
                    child: const Text('刷新源', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            for (final src in _sources.sources)
              if (_sources.errorsBySource.containsKey(src.id))
                MarketSourceErrorBox(
                  label: src.label,
                  message: _sources.errorsBySource[src.id]!,
                  onRetry: () => unawaited(_sources.refresh()),
                ),
            if (_source.status == MarketStatus.failed)
              MarketErrorBox(
                message: _source.error,
                onRetry: () => _source.load(force: true),
              ),
            if (_source.status == MarketStatus.ready && _source.fromCache)
              MarketNoteBox(
                text: '网络没通，用的是上次缓存的目录（${formatMarketWhen(_source.fetchedAt)}）',
              ),
            const SizedBox(height: 6),
          ],
        ),
      );
}