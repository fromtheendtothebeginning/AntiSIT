import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:campus_core/campus_core.dart';

import 'market/market_page.dart';
import 'ext_open.dart';
import 'ext_order_page.dart';
import 'extension_item.dart';
import 'extension_store.dart';
import 'extensions_page_actions.dart';
import 'extensions_page_card.dart';
import 'extensions_page_consent.dart';
import 'extensions_page_dialogs.dart';
import 'market/market_installer.dart';
import 'market/market_source.dart';
import 'market/market_sources.dart';
import 'market/market_sources_view.dart';

/// 「拓展」页：网页形态的小功能，用户自己加进来。
///
/// 单页列出自己的拓展（加法与市场都收进「添加拓展」）；加进来的每条以卡片呈现，
/// 点开就是对应网页，网页里带着 `antiSIT` 那套接口。
class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({super.key});

  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  ExtensionStore get _store => ExtensionStore.I;

  /// 是否处于整理状态：长按卡片进入，可拖位 / 顶部尺寸条 / 拖右下角弧线改大小。
  bool _editing = false;

  /// 当前选中的拓展卡片（顶部尺寸条作用于它，也只有它显示缩放弧线）。
  String? _selectedCardId;

  /// 本机 App 版本：判已装拓展的「需升级 App」（导入的 JSON 也能声明最低版本）。
  String _appVersion = '';

  /// 市场目录在 MarketView.initState 里加载时会同步 notify；那时本页可能正在
  /// build，直接 setState 会炸。统一挪到下一帧，多次通知只排一次。
  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
    // 市场目录 / 第三方源加载完后，「可更新」角标要跟着出现
    MarketSource.I.addListener(_onChanged);
    ExtSourceStore.I.addListener(_onChanged);
    if (!_store.loaded) unawaited(_store.load());
    // 演示模式的目录是本地假数据（不打网络）：进页面就拉，角标与跳市场才能立刻工作
    if (AppState.I.demo && MarketSource.I.status == MarketStatus.idle) {
      unawaited(MarketSource.I.load());
    }
    unawaited(_readAppVersion());
  }

  Future<void> _readAppVersion() async {
    final v = await ExtensionItem.appVersionLoader();
    if (mounted && v.isNotEmpty) setState(() => _appVersion = v);
  }

  void _onChanged() {
    if (!mounted) return;
    // 市场目录在本页 build 期间同步 notify：只在 build 阶段挪到下一帧，平时立即重建。
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_rebuildScheduled) return;
      _rebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rebuildScheduled = false;
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    MarketSource.I.removeListener(_onChanged);
    ExtSourceStore.I.removeListener(_onChanged);
    super.dispose();
  }

  /// 打开拓展；有新版就直接跳到插件市场并定位到这条，用户在那儿更新。
  Future<void> _open(ExtensionItem e) async {
    if (_isUpdatable(e)) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MarketPage(focusId: e.id)),
      );
      return;
    }
    openExtension(context, e, onMessage: _toast);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(fontSize: 13)),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// 「添加拓展」：三种加法，另加一项「插件市场」（市场是自己的独立页）。
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
              subtitle: const Text(
                '给它起个名字，填一个 http(s) 网址',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 'url'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('导入 Cordis 压缩包'),
              subtitle: const Text(
                'ext.json + main.js 打成 zip；导入后自动解压',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 'zip'),
            ),
            ListTile(
              leading: const Icon(Icons.data_object_rounded),
              title: const Text('导入 JSON'),
              subtitle: const Text(
                '粘贴一份拓展 JSON（单条或数组）',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 'json'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('插件市场'),
              subtitle: const Text(
                '从市场目录里发现并安装别人做的拓展',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 'market'),
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
      case 'market':
        await _openMarketPage();
    }
  }

  /// 打开独立的插件市场页。
  Future<void> _openMarketPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MarketPage(onInstalled: _toast)),
    );
    if (mounted) setState(() {});
  }

  /// 填写网址 / 编辑 / 看详情：同一个弹窗；[isNew] 决定按钮与写盘方式。
  Future<void> _edit({
    ExtensionItem? item,
    bool isNew = true,
    bool readOnly = false,
  }) async {
    final out = await showDialog<ExtensionItem>(
      context: context,
      builder: (_) =>
          ExtensionEditDialog(item: item, isNew: isNew, readOnly: readOnly),
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

  Future<void> _importBundle() => importExtensionBundle(
        context: context,
        store: _store,
        toast: _toast,
      );

  Future<void> _importJson() => importExtensionJson(
        context: context,
        store: _store,
        toast: _toast,
      );

  /// 扫一扫加拓展：网址 → 加一条 web 拓展；规定格式的安装码 → 下载安装。
  /// 码型识别与结果面板在扫码插件里，这里只处理「用户确认后」的落库动作。
  Future<void> _scanExtension(ScanCapability scan) async {
    final outcome = await scan.open(context, mode: ScanMode.addExtension);
    if (!mounted || outcome == null) return;
    switch (outcome) {
      case ScanLinkOutcome link:
        await _addScannedLink(link.url);
      case ScanBundleOutcome bundle:
        await _installScannedBundle(bundle);
      case ScanSourceOutcome source:
        await addScannedSource(context, source, onMessage: _toast);
    }
  }

  /// 把扫到的网址作为 web 拓展加进来：名称默认用域名，弹窗里仍可改。
  Future<void> _addScannedLink(String url) async {
    final normalized = ExtensionItem.normalizeUrl(url) ?? url;
    final host = Uri.tryParse(normalized)?.host ?? '';
    final preset = ExtensionItem(
      id: ExtensionItem.newId(),
      name: host,
      url: normalized,
    );
    final item = await showDialog<ExtensionItem>(
      context: context,
      builder: (_) => ExtensionEditDialog(item: preset, isNew: true),
    );
    if (item == null) return;
    await _store.add(item);
    _toast('已添加「${item.name}」');
  }

  Future<void> _installScannedBundle(ScanBundleOutcome code) =>
      installScannedExtension(
        context: context,
        store: _store,
        toast: _toast,
        code: code,
      );

  Future<void> _itemMenu(ExtensionItem e) async {
    final builtin = _store.isBuiltin(e.id);
    if (!mounted) return;
    final pick = await showExtensionItemMenu(
      context,
      e,
      builtin: builtin,
      demo: AppState.I.demo,
    );
    if (!mounted) return;
    switch (pick) {
      case 'demo-downgrade':
        await _store.demoResetNote();
        _toast('演示记事本已降回 v1.0.0，点它重走跳转流程');
      case 'detail':
        await _edit(item: e, isNew: false, readOnly: true);
      case 'consent':
        await _manageConsent(e);
      case 'edit':
        await _edit(item: e, isNew: false);
      case 'delete':
        if (!await confirmRemoveExtension(context, e)) return;
        await _store.remove(e.id);
        _toast('已删除「${e.name}」');
    }
  }

  Future<void> _manageConsent(ExtensionItem e) =>
      manageExtensionConsent(context, e, toast: _toast);

  void _setEditing(bool value) {
    if (_editing == value) return;
    setState(() {
      _editing = value;
      if (!value) _selectedCardId = null;
    });
  }

  void _selectCard(String id) {
    if (!_editing || _selectedCardId == id) return;
    setState(() => _selectedCardId = id);
  }

  /// 隐藏全部网址的总开关（卡片上那一行直接不显示，详情里照旧能看到）。
  Future<void> _toggleHideUrls() => _store.setHideUrls(!_store.hideUrls);

  /// 打开排序页：拖完回来宫格按新顺序排（排序结果由 store 落盘）。
  Future<void> _openSorter() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ExtensionOrderPage()));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scan = PluginRegistry.I.capability<ScanCapability>(PluginIds.scan);
    final items = _store.items;
    final hide = _store.hideUrls;
    final selectedId = items.any((e) => e.id == _selectedCardId)
        ? _selectedCardId
        : null;
    final selectedSize = selectedId == null ? null : _store.sizeOf(selectedId);
    // 整页监听 AppState：悬浮玻璃顶栏开关改完要连 Scaffold 一起重建
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        // 顶栏留白必须在 builder 里算（读 AppState 的开关），且要在建 Scaffold 之前取
        // （body 里的 MediaQuery 已被扣掉状态栏，issue #12）。
        final topInset = glassTopInset(context);
        final myPage = items.isEmpty
            ? _empty(context, topInset)
            : _grid(context, items, selectedId, topInset);
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(
            context,
            title: const Text('拓展'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _editing
                    ? TextButton(
                        onPressed: () => _setEditing(false),
                        style: TextButton.styleFrom(
                          foregroundColor: SemColors.accent,
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('完成'),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 扫一扫：扫一扫插件在就显示（按能力取用，不 import 它的包）
                          if (scan != null)
                            _roundAction(
                              Icons.qr_code_scanner_outlined,
                              '扫一扫',
                              () => _scanExtension(scan),
                            ),
                          ...[
                            _roundAction(
                              hide
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              hide ? '显示全部网址' : '隐藏全部网址',
                              items.isEmpty ? null : _toggleHideUrls,
                              color: hide ? SemColors.accent : null,
                            ),
                            // 只有一条时本来没得排，但改过尺寸还需要从排序页「重置大小」
                            if (items.length > 1 || _store.hasCustomSizes)
                              _roundAction(
                                Icons.swap_vert_rounded,
                                '排序拓展',
                                _openSorter,
                              ),
                            _roundAction(Icons.add, '添加拓展', _addMenu),
                          ],
                        ],
                      ),
              ),
            ],
          ),
          // 单页：只列自己的拓展；加法与市场都收进「添加拓展」页
          body: GlassFadedBody(
            barHeight: topInset,
            child: Column(
            children: [
              Expanded(
                // 编辑态卡片自己不吃点击（onTap 为 null），用 translucent 让点空白处落到这一层
                child: _editing
                    ? GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _setEditing(false),
                        child: myPage,
                      )
                    : myPage,
              ),
              // 尺寸条放在页面下方、底栏上方：单手握持时拇指正好够得着
              if (_editing && items.isNotEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    4,
                    14,
                    8 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: CardSizeBar(
                    size: selectedSize,
                    onChanged: (size) {
                      final id = selectedId;
                      if (id != null) unawaited(_store.setSize(id, size));
                    },
                  ),
                ),
            ],
          ),
          ),
        );
      },
    );
  }

  /// 「我的」页空态：三种加法，外加去「添加拓展」页（市场在那里）。
  Widget _empty(BuildContext context, double topInset) => SingleChildScrollView(
    // 底栏是玻璃浮层（壳层 Scaffold.extendBody）：滚动底部让出底栏这一截
    padding: EdgeInsets.fromLTRB(
      20,
      20 + topInset,
      20,
      20 + MediaQuery.paddingOf(context).bottom,
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AppCard(
          child: Column(
            children: [
              Icon(
                Icons.extension_outlined,
                size: 40,
                color: SemColors.textMuted,
              ),
              const SizedBox(height: 12),
              const Text(
                '还没有拓展',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '拓展是网页形态的小功能：填一个网址、导入一份 html/js/css 压缩包，'
                '或粘贴一份拓展 JSON 都行。加进来就会以卡片出现在这里，点开即用。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: SemColors.textMuted,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.tonal(
                    onPressed: _openMarketPage,
                    child: const Text('去市场看看'),
                  ),
                  OutlinedButton(
                    onPressed: () => _edit(),
                    child: const Text('填写网址'),
                  ),
                  OutlinedButton(
                    onPressed: _importBundle,
                    child: const Text('导入压缩包'),
                  ),
                  OutlinedButton(
                    onPressed: _importJson,
                    child: const Text('导入 JSON'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '打开的网页带着 antiSIT 接口：读 App 配色、用自己的本地存储、弹提示、关页面。'
                'App 里的用户数据（学号 / 课表 / 成绩）不会给出去。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: SemColors.textMuted,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _grid(
    BuildContext context,
    List<ExtensionItem> items,
    String? selectedId,
    double topInset,
  ) =>
      CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: FlexibleCardGrid(
              // 顶部让出悬浮顶栏
              padding: EdgeInsets.fromLTRB(14, 12 + topInset, 14, 0),
              items: [
                for (final e in items)
                  FlexibleGridItem(
                    id: e.id,
                    size: _store.sizeOf(e.id),
                    builder: (context, size, editing) => ExtensionCard(
                      item: e,
                      size: size,
                      editing: editing,
                      hideUrls: _store.hideUrls,
                      appVersion: _appVersion,
                      updatable: _isUpdatable(e),
                      onOpen: () => _open(e),
                      onMore: () => _itemMenu(e),
                    ),
                  ),
              ],
              selectedId: selectedId,
              onSelected: _selectCard,
              editing: _editing,
              onEditingChanged: _setEditing,
              onOrderChanged: (ids) => _store.setOrder(ids),
              onSizeChanged: (id, size) => _store.setSize(id, size),
            ),
          ),
          SliverPadding(
            // 底栏是玻璃浮层：最后一张卡要能滚出底栏上方；整理态时那份留白交给尺寸条。
            padding: EdgeInsets.fromLTRB(
              14,
              12,
              14,
              _editing ? 12 : 24 + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverToBoxAdapter(child: ExtensionAddCard(onTap: _addMenu)),
          ),
        ],
      );

  /// 顶栏按钮：用全站统一的悬浮玻璃圆钮（40 直径、thumb 玻璃面 + 描边、无投影）。
  Widget _roundAction(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    Color? color,
  }) =>
      glassTopBarAction(
        IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: 22, color: color ?? SemColors.textSecondary),
          padding: EdgeInsets.zero,
        ),
        edge: 4,
      );

  /// 市场里这条有没有新版：目录还没拉到时返回 false，拉到后监听会重建。
  bool _isUpdatable(ExtensionItem e) {
    if (!e.fromMarket) return false;
    final installer = MarketInstaller();
    for (final entry in [
      ...MarketSource.I.entries,
      ...ExtSourceStore.I.allEntries,
    ]) {
      if (entry.id != e.id || entry.sourceId != e.sourceId) continue;
      return installer.hasUpdate(entry);
    }
    return false;
  }
}
