import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:campus_core/campus_core.dart';

import 'bundle_import.dart';
import 'cordis_bundle.dart';
import 'ext_bridge.dart';
import 'ext_icon.dart';
import 'ext_open.dart';
import 'extension_item.dart';
import 'extension_store.dart';
import 'market/market_installer.dart';
import 'market/market_source.dart';
import 'market/market_sources.dart';
import 'market/market_view.dart';

/// 「拓展」页：网页形态的小功能，用户自己加进来。
///
/// 两个标签：**我的**（自己加的与装进来的）与**市场**（[MarketView]，从插件市场装）。
/// 子页滑到边界后继续拖，拖动经 [NavSwipeHost] 转给主界面，把两个子页接进
/// 主界面的滑动链：`… 工具 ⇄ 拓展·我的 ⇄ 拓展·市场 ⇄ 我的 …`。
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

  /// 滑块的连续位置 / 页面区域拖动中的位置（与连接设置、主界面切页同一套）。
  final ValueNotifier<double> _tabPos = ValueNotifier<double>(0);
  final ValueNotifier<double?> _tabDrag = ValueNotifier<double?>(null);

  /// 本次手势的连续（**未 clamp**）位置：越界量按它算，拖回来时越界量才会
  /// 跟着归零——若以 clamp 后的位置为基准，回程会被吃掉，主界面弹过锚点
  /// 冲向另一边。松手 / 取消时清空。
  double? _dragRaw;

  /// 市场页第一次要被看到时再建：拓展页会被主界面离屏预建，
  /// 一上来就建它会把市场目录的网络请求带到启动阶段。
  bool _marketMounted = false;

  /// 主界面滑页桥（[NavSwipeScope]）：build 里取，树上没有（独立运行 / 单测）
  /// 就是 null，越界拖动就地吞掉，与接桥前行为一致。
  NavSwipeHost? _navHost;

  /// 本机 App 版本：判已装拓展的「需升级 App」（导入的 JSON 也能声明最低版本，
  /// 没有市场那道安装门，列表提示与打开拦截就是唯一检查点）。
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
    _tabPos.value = _tab.toDouble();
    if (!_store.loaded) unawaited(_store.load());
    unawaited(_readAppVersion());
  }

  Future<void> _readAppVersion() async {
    final v = await ExtensionItem.appVersionLoader();
    if (mounted && v.isNotEmpty) setState(() => _appVersion = v);
  }

  void _onChanged() {
    if (!mounted) return;
    // 市场目录在 MarketView.initState 里加载时会同步 notify；那时本页正在 build，
    // 直接 setState 会炸。只在 build 阶段挪到下一帧，平时立即重建。
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
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
    _tabPos.dispose();
    _tabDrag.dispose();
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
              title: const Text('导入 Cordis 压缩包'),
              subtitle: const Text('ext.json + main.js 打成 zip；导入后自动解压',
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

    final bytes = await picked.readAsBytes();
    final CordisManifest manifest;
    try {
      manifest = readBundleManifest(bytes);
    } on FormatException catch (e) {
      _toast(e.message);
      return;
    } catch (e) {
      _toast('读取压缩包失败：$e');
      return;
    }
    if (_store.items.any((e) => e.id == manifest.id)) {
      _toast('已存在 id 为「${manifest.id}」的拓展，请先删除或让作者换一个 id');
      return;
    }

    ExtBundle bundle;
    try {
      bundle = extractBundle(bytes: bytes, dir: await _store.bundleDir(manifest.id));
    } on FormatException catch (e) {
      _toast(e.message);
      return;
    } catch (e) {
      _toast('解压失败：$e');
      return;
    }
    if (!mounted) return;

    // 清单已经带了名称 / 简介 / 权限，导入后仍让用户确认卡片显示值。
    final preset = ExtensionItem(
      id: manifest.id,
      name: manifest.name,
      url: bundle.entry,
      desc: manifest.desc,
      bundled: true,
      runtime: ExtensionItem.runtimeCordis,
      version: manifest.version,
      permissions: manifest.permissions,
      minAppVersion: manifest.minAppVersion,
    );
    final item = await showDialog<ExtensionItem>(
      context: context,
      builder: (_) => _AddEditDialog(item: preset, isNew: true),
    );
    if (item == null) {
      await _store.deleteBundleDir(manifest.id); // 用户取消了：把刚解压出来的目录一并清掉
      return;
    }
    await _store.add(item);
    _toast('已导入「${item.name}」');
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

  void _setTab(int i) {
    if (i == _tab) return;
    if (i == 1) _marketMounted = true;
    setState(() => _tab = i);
  }

  // ── 页面区域左右滑动切「我的 / 市场」（与主界面、连接设置同一套：
  //    拖过一半就换，快速甩动借动量多滑一格；页面内部接住横滑的照旧优先）──

  void _onTabDragStart(DragStartDetails _) {
    _tabDrag.value = _tabPos.value;
    _dragRaw = _tabPos.value;
    // 邻页得在树里才能跟着滑进来
    if (!_marketMounted) setState(() => _marketMounted = true);
  }

  void _onTabDragUpdate(DragUpdateDetails d) {
    final w = MediaQuery.sizeOf(context).width;
    if (w <= 0) return;
    // 内容往左拖 = 去下一格；连续位置先不 clamp，滑出边界的部分转给主界面
    final raw = (_dragRaw ?? _tabPos.value) - d.delta.dx / w;
    _dragRaw = raw;
    _tabDrag.value = raw.clamp(0.0, 1.0);
    // 「界面实时跟着滑块切换」关掉时等松手落位再换
    if (AppState.I.followSlider) _setTab(_tabDrag.value!.round());
    // 越界部分镜像给主界面（工具 ← 我的｜市场 → 我的）：主页面跟着手指连续
    // 滑过去，拖回界内越界量归零、主界面位置也跟着弹回拓展格
    _navHost?.navDragOver(raw < 0 ? raw : (raw > 1 ? raw - 1 : 0));
  }

  void _onTabDragEnd(DragEndDetails d) {
    final w = MediaQuery.sizeOf(context).width;
    final v = (-d.velocity.pixelsPerSecond.dx / (w <= 0 ? 1 : w)).clamp(-8.0, 8.0);
    var target = (_tabDrag.value ?? _tabPos.value).round().clamp(0, 1);
    final next = target + (v > 0 ? 1 : -1);
    if (v.abs() >= 5.0 && next >= 0 && next <= 1) target = next;
    _tabDrag.value = null; // 交还弹簧：滑块从当前位置弹到落点
    _dragRaw = null;
    _setTab(target);
    // 越界拖动的落位交给主界面就近落格（没到过界外时它自己会忽略）
    _navHost?.navDragEnd(d.velocity.pixelsPerSecond.dx);
  }

  /// 隐藏全部网址的总开关（卡片上那一行直接不显示，详情里照旧能看到）。
  /// 藏在标题栏是因为它管的是「整页要不要露网址」，摆在页面上会一直占位置。
  Future<void> _toggleHideUrls() => _store.setHideUrls(!_store.hideUrls);

  @override
  Widget build(BuildContext context) {
    _navHost = NavSwipeScope.of(context);
    final scan = PluginRegistry.I.capability<ScanCapability>(PluginIds.scan);
    final items = _store.items;
    final hide = _store.hideUrls;
    final market = _tab == 1;
    // 两页都留在树里：横滑时一起位移，State（搜索词、滚动位置）也不会切走就丢。
    // 市场页仍按需挂载，见 _marketMounted。
    final panels = <Widget>[
      items.isEmpty ? _empty() : _grid(items),
      if (market || _marketMounted) MarketView(onInstalled: _toast),
    ];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        centerTitle: true,
        title: const Text('拓展',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 1)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 扫一扫：扫一扫插件在就显示（按能力取用，不 import 它的包）
                if (scan != null)
                  _roundAction(Icons.qr_code_scanner_outlined, '扫一扫',
                      () => scan.open(context)),
                if (market)
                  _roundAction(Icons.refresh_rounded, '重新拉市场目录',
                      () => unawaited(MarketSource.I.load(force: true)))
                else ...[
                  _roundAction(
                    hide ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    hide ? '显示全部网址' : '隐藏全部网址',
                    items.isEmpty ? null : _toggleHideUrls,
                    color: hide ? SemColors.accent : null,
                  ),
                  _roundAction(Icons.add, '添加拓展', _addMenu),
                ],
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: GlassTabs(
              labels: const ['我的', '市场'],
              height: 38,
              fontSize: 13.5,
              index: _tab,
              position: _tabPos,
              dragPosition: _tabDrag,
              onChanged: _setTab,
            ),
          ),
          Expanded(
            child: GestureDetector(
              // translucent：页面空白处也能起手势；内层真接住横滑的（搜索框选词等）优先
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _onTabDragStart,
              onHorizontalDragUpdate: _onTabDragUpdate,
              onHorizontalDragEnd: _onTabDragEnd,
              onHorizontalDragCancel: () {
                _tabDrag.value = null;
                _dragRaw = null;
                _navHost?.navDragCancel();
              },
              child: ValueListenableBuilder<double>(
                valueListenable: _tabPos,
                builder: (context, rawPos, _) {
                  // 开关关掉时界面不跟滑块连续滑，只按已落位的那一格显示（松手才换）
                  final pos = AppState.I.followSlider ? rawPos : _tab.toDouble();
                  final w = MediaQuery.sizeOf(context).width;
                  return Stack(
                    children: [
                      for (var k = 0; k < panels.length; k++)
                        Positioned.fill(
                          // 只画当前页和拖动时露出的邻页
                          child: Offstage(
                            offstage: (k - pos).abs() >= 0.999,
                            child: Transform.translate(
                              offset: Offset((k - pos) * w, 0),
                              child: panels[k],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
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

  Widget _grid(List<ExtensionItem> items) => CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                // 纵向压缩版：图标 36 + 标题 + 单行简介 + 来源/版本
                mainAxisExtent: 128,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => _card(items[i]),
                childCount: items.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            sliver: SliverToBoxAdapter(child: _addCard()),
          ),
        ],
      );

  Widget _roundAction(IconData icon, String tooltip, VoidCallback? onPressed,
          {Color? color}) =>
      Padding(
        padding: const EdgeInsets.only(left: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SemColors.card.withValues(alpha: 0.72),
            border: Border.all(color: SemColors.border),
            boxShadow: [
              BoxShadow(
                  color: SemColors.shadow, blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon, size: 22, color: color ?? SemColors.textSecondary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 42, height: 42),
          ),
        ),
      );

  /// 市场里这条有没有新版：目录还没拉到时返回 false，拉到后监听会重建。
  bool _isUpdatable(ExtensionItem e) {
    if (!e.fromMarket) return false;
    final installer = MarketInstaller();
    for (final entry in [...MarketSource.I.entries, ...ExtSourceStore.I.allEntries]) {
      if (entry.id != e.id || entry.sourceId != e.sourceId) continue;
      return installer.hasUpdate(entry);
    }
    return false;
  }

  Widget? _badge(ExtensionItem e) {
    if (e.needsNewerApp(_appVersion)) {
      return Capsule('需升级 App', color: SemColors.danger);
    }
    if (_isUpdatable(e)) return Capsule('可更新', color: SemColors.warning);
    if (e.builtin) return Capsule('内置', color: SemColors.textMuted);
    return Capsule('已安装', color: SemColors.success);
  }

  /// 卡片底部左侧：远程写域名，本地包写来源（版本单独靠右）。
  String _sourceLabel(ExtensionItem e) {
    if (!e.bundled) {
      final host = Uri.tryParse(e.url)?.host ?? '';
      return host.isEmpty ? e.url : host;
    }
    if (e.runtime == ExtensionItem.runtimeLegacy) return '旧版网页拓展（需迁移）';
    if (!e.fromMarket) return '本地 Cordis';
    return '插件市场 · Cordis';
  }

  Widget _moreButton(ExtensionItem e) => Tooltip(
        message: e.builtin ? '详情' : '编辑 / 删除',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _itemMenu(e),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SemColors.card.withValues(alpha: 0.72),
              border: Border.all(color: SemColors.border),
            ),
            child: Icon(Icons.more_horiz, size: 18, color: SemColors.textMuted),
          ),
        ),
      );

  Widget _card(ExtensionItem e) {
    final badge = _badge(e);
    final version = e.version.isEmpty ? '' : 'v${e.version}';
    // 眼睛开关只隐藏网址：本地 / 市场来源与版本不是 URL，照旧显示
    final showSource = !_store.hideUrls || e.bundled;
    final showFooter = showSource || version.isNotEmpty;
    return AppCard(
      bottomGap: 0,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      onTap: () => _open(e),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExtIcon(item: e),
              const Spacer(),
              if (badge != null) ...[badge, const SizedBox(width: 4)],
              _moreButton(e),
            ],
          ),
          const SizedBox(height: 6),
          Text(e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15, height: 1.15)),
          const SizedBox(height: 2),
          SizedBox(
            height: 15,
            child: Text(e.desc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5, height: 1.25, color: SemColors.textSecondary)),
          ),
          const Spacer(),
          if (showFooter)
            Row(
              children: [
                if (showSource) ...[
                  if (!e.bundled) ...[
                    Icon(Icons.public, size: 12, color: SemColors.textMuted),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(_sourceLabel(e),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: SemColors.textMuted)),
                  ),
                ] else
                  const Spacer(),
                if (version.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(version,
                      style: TextStyle(fontSize: 10.5, color: SemColors.textMuted)),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _addCard() => SizedBox(
        height: 56,
        child: CustomPaint(
          painter: _DashedBorderPainter(
              color: SemColors.borderStrong.withValues(alpha: 0.55)),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _addMenu,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: SemColors.borderStrong),
                    ),
                    child: Icon(Icons.add_rounded,
                        size: 18, color: SemColors.textSecondary),
                  ),
                  const SizedBox(width: 10),
                  Text('添加拓展',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: SemColors.textSecondary)),
                ],
              ),
            ),
          ),
        ),
      );
}

/// 虚线圆角边框：给「添加拓展」占位卡用（不引第三方 dashed border 包）。
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  static const double radius = 16;
  static const double dash = 6;
  static const double gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
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
                  labelText: '图标（可空）',
                  hintText: 'line:handyman / 图片网址 / emoji；留空用网站 favicon'),
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
