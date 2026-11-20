import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:campus_core/campus_core.dart';

import 'bundle_import.dart';
import 'cordis_bundle.dart';
import 'ext_bridge.dart';
import 'ext_consent.dart';
import 'ext_icon.dart';
import 'ext_open.dart';
import 'ext_order_page.dart';
import 'ext_permissions.dart';
import 'extension_item.dart';
import 'extension_store.dart';
import 'market/market_installer.dart';
import 'market/market_source.dart';
import 'market/market_sources.dart';
import 'market/market_sources_view.dart';
import 'market/market_view.dart';
import 'scanned_install.dart';

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

  /// 「我的」页是否处于整理状态：长按卡片进入，可拖位 / 顶部尺寸条 / 拖右下角弧线改大小。
  bool _editing = false;

  /// 当前选中的拓展卡片（顶部尺寸条作用于它，也只有它显示缩放弧线）。
  String? _selectedCardId;

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
    _tabPos.dispose();
    _tabDrag.dispose();
    super.dispose();
  }

  // ==================== 打开 ====================

  Future<void> _open(ExtensionItem e) =>
      openExtension(context, e, onMessage: _toast);

  // ==================== 添加 ====================

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
  Future<void> _edit({
    ExtensionItem? item,
    bool isNew = true,
    bool readOnly = false,
  }) async {
    final out = await showDialog<ExtensionItem>(
      context: context,
      builder: (_) =>
          _AddEditDialog(item: item, isNew: isNew, readOnly: readOnly),
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
      picked = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: '拓展压缩包', extensions: ['zip']),
        ],
      );
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
      bundle = extractBundle(
        bytes: bytes,
        dir: await _store.bundleDir(manifest.id),
      );
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
      context: context,
      builder: (_) => const _ImportDialog(),
    );
    if (list == null || !mounted) return;
    for (final item in list) {
      await _store.add(item);
    }
    _toast('已导入 ${list.length} 个拓展');
  }

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
      builder: (_) => _AddEditDialog(item: preset, isNew: true),
    );
    if (item == null) return;
    await _store.add(item);
    _toast('已添加「${item.name}」');
  }

  /// 下载 + 校验扫码得到的拓展包：下载过程弹不可取消的进度框，
  /// 校验通过后把包里的名称 / id / 版本 / 权限列给用户，确认才解压入列。
  Future<void> _installScannedBundle(ScanBundleOutcome code) async {
    final installer = ScannedBundleInstaller(store: _store);
    final result = await showDialog<Object?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadDialog(
        label: '正在下载拓展…',
        task: () => installer.download(code),
      ),
    );
    if (!mounted) return;
    if (result is _DownloadFailure) {
      _toast(_scanError(result.error));
      return;
    }
    if (result is! ScannedBundle) return;
    final bundle = result;

    final ok = await _confirmScannedInstall(bundle, code.url);
    if (!mounted || !ok) return;
    try {
      final item = await installer.install(bundle);
      _toast('已安装「${item.name}」');
    } catch (e) {
      _toast(_scanError(e));
    }
  }

  /// 安装前确认：包里的清单（不是二维码里写的）才是最终内容，权限尤其要看清楚。
  Future<bool> _confirmScannedInstall(ScannedBundle bundle, String url) async {
    final m = bundle.manifest;
    final perms = m.permissions.isEmpty
        ? '无'
        : describeSensitivePermissions(m.permissions).join('\n');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('安装「${m.name}」？'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.5,
          ),
          child: SingleChildScrollView(
            child: Text(
              'id：${m.id}\n'
              '版本：${m.version}\n'
              '来源：$url\n\n'
              '敏感权限：\n$perms',
              style: const TextStyle(fontSize: 12.5, height: 1.6),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('安装'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// 把下载 / 解压错误翻成一句能给用户看的提示。
  static String _scanError(Object e) {
    if (e is FormatException) return e.message;
    if (e is StateError) return e.message;
    if (e is TimeoutException) return '下载超时，请检查网络后重试';
    return '$e';
  }

  // ==================== 单条菜单 ====================

  Future<void> _itemMenu(ExtensionItem e) async {
    final builtin = _store.isBuiltin(e.id);
    if (!mounted) return;
    final pick = await showModalBottomSheet<String>(
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

  /// 权限管理：静态权限只读展示；运行时授权逐项开关。
  Future<void> _manageConsent(ExtensionItem e) async {
    final grants = await ExtConsentService.I.grants(e.id);
    if (!mounted) return;
    final staticLabels = describeSensitivePermissions(e.permissions);
    final caps = <String>{
      if (e.permissions.contains('notification')) 'notification.popup',
      if (e.permissions.contains('clipboard')) 'clipboard.read',
      if (e.permissions.contains('background')) 'background.keepalive',
      ...grants.keys,
    }.toList()..sort();
    final state = <String, bool?>{for (final cap in caps) cap: grants[cap]};
    final reset = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('「${e.name}」的权限'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (staticLabels.isNotEmpty) ...[
                    const Text(
                      '安装时声明（只读）',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final label in staticLabels)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_outline, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                  const Text(
                    '运行时授权',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  if (caps.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '这个拓展没有需要单独确认的能力。',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  for (final cap in caps)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(ExtConsentService.describe(cap)),
                      subtitle: Text(
                        state[cap] == true
                            ? '已允许'
                            : (state[cap] == false ? '已拒绝' : '未申请；插件用到时会询问'),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      value: state[cap] == true,
                      onChanged: (value) async {
                        if (value) {
                          await ExtConsentService.I.allow(e.id, cap);
                        } else {
                          await ExtConsentService.I.deny(e.id, cap);
                        }
                        setDialog(() => state[cap] = value);
                      },
                    ),
                  const SizedBox(height: 6),
                  const Text(
                    '关闭后，插件下次用到这项能力会重新询问或直接拒绝；'
                    '弹窗通知会立即停止。',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('关闭'),
            ),
            if (caps.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('全部重置'),
              ),
          ],
        ),
      ),
    );
    if (reset == true) {
      await ExtConsentService.I.revokeAll(e.id);
      _toast('已重置「${e.name}」的运行时授权');
    }
  }

  // ==================== 界面 ====================

  void _setTab(int i) {
    if (i == _tab) return;
    if (i == 1) _marketMounted = true;
    setState(() {
      _tab = i;
      // 切去市场时不保留整理状态：回来时不会突然多出一排尺寸条 / 角标
      if (i == 1) {
        _editing = false;
        _selectedCardId = null;
      }
    });
  }

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
    final v = (-d.velocity.pixelsPerSecond.dx / (w <= 0 ? 1 : w)).clamp(
      -8.0,
      8.0,
    );
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

  /// 打开排序页：拖完回来宫格按新顺序排（排序结果由 store 落盘）。
  Future<void> _openSorter() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ExtensionOrderPage()));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _navHost = NavSwipeScope.of(context);
    final scan = PluginRegistry.I.capability<ScanCapability>(PluginIds.scan);
    final items = _store.items;
    final hide = _store.hideUrls;
    final market = _tab == 1;
    final selectedId = items.any((e) => e.id == _selectedCardId)
        ? _selectedCardId
        : null;
    final selectedSize = selectedId == null ? null : _store.sizeOf(selectedId);
    // 两页都留在树里：横滑时一起位移，State（搜索词、滚动位置）也不会切走就丢。
    // 市场页仍按需挂载，见 _marketMounted。
    final myPage = items.isEmpty
        ? _empty(context)
        : _grid(context, items, selectedId);
    final panels = <Widget>[
      Column(
        children: [
          Expanded(child: myPage),
          // 尺寸条放在页面下方、底栏上方：顶部那块地方留给标题和两个圆形按钮，
          // 单手握持时拇指正好够得着（顶栏那排按钮要伸上去）。
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
      if (market || _marketMounted) MarketView(onInstalled: _toast),
    ];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        centerTitle: true,
        title: const Text(
          '拓展',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
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
                      // 扫一扫：扫一扫插件在就显示（按能力取用，不 import 它的包）。
                      // 从这页进去的扫码会把网址 / 拓展安装码带回来，直接用。
                      if (scan != null)
                        _roundAction(
                          Icons.qr_code_scanner_outlined,
                          '扫一扫',
                          () => _scanExtension(scan),
                        ),
                      if (market)
                        _roundAction(
                          Icons.refresh_rounded,
                          '重新拉市场目录',
                          () => unawaited(MarketSource.I.load(force: true)),
                        )
                      else ...[
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
              // 整理态点空白（卡片下方 / 卡片缝里）也退出；卡片自己会吸收点击
              onTap: _editing ? () => _setEditing(false) : null,
              // 整理卡片时不切子页：横向拖动要留给卡片 / 手柄，避免刚拖到一半整页滑走
              onHorizontalDragStart: _editing ? null : _onTabDragStart,
              onHorizontalDragUpdate: _editing ? null : _onTabDragUpdate,
              onHorizontalDragEnd: _editing ? null : _onTabDragEnd,
              onHorizontalDragCancel: _editing
                  ? null
                  : () {
                      _tabDrag.value = null;
                      _dragRaw = null;
                      _navHost?.navDragCancel();
                    },
              child: ValueListenableBuilder<double>(
                valueListenable: _tabPos,
                builder: (context, rawPos, _) {
                  // 开关关掉时界面不跟滑块连续滑，只按已落位的那一格显示（松手才换）
                  final pos = AppState.I.followSlider
                      ? rawPos
                      : _tab.toDouble();
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

  Widget _empty(BuildContext context) => Center(
    child: SingleChildScrollView(
      // 底栏是玻璃浮层（壳层 Scaffold.extendBody）：滚动底部让出底栏这一截
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
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
                    onPressed: () => setState(() => _tab = 1),
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
  ) => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: FlexibleCardGrid(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          items: [
            for (final e in items)
              FlexibleGridItem(
                id: e.id,
                size: _store.sizeOf(e.id),
                builder: (context, size, editing) => _card(e, size, editing),
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
        // 底栏是玻璃浮层（壳层 Scaffold.extendBody）：最后一张卡也要能滚出底栏上方。
        // 整理态时尺寸条贴在底栏上方，那份留白交给它，别再重复叠一次。
        padding: EdgeInsets.fromLTRB(
          14,
          12,
          14,
          _editing ? 12 : 24 + MediaQuery.paddingOf(context).bottom,
        ),
        sliver: SliverToBoxAdapter(child: _addCard()),
      ),
    ],
  );

  Widget _roundAction(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    Color? color,
  }) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // card 本身带透明度，withValues 会覆盖掉 alpha（深色下变近白）：
        // 先与页面底色合成，得到实底又不发白
        color: Color.alphaBlend(SemColors.card, SemColors.bg),
        border: Border.all(color: SemColors.border),
        boxShadow: [
          BoxShadow(
            color: SemColors.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
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
    for (final entry in [
      ...MarketSource.I.entries,
      ...ExtSourceStore.I.allEntries,
    ]) {
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

  /// 紧凑尺寸下用的小圆点状态：只标「需升级 App / 可更新」这类要处理的事，
  /// 内置 / 已安装不打扰。完整胶囊仍只在默认尺寸里显示。
  Color? _statusColor(ExtensionItem e) {
    if (e.needsNewerApp(_appVersion)) return SemColors.danger;
    if (_isUpdatable(e)) return SemColors.warning;
    return null;
  }

  /// 图标 + 右上角状态点（紧凑尺寸用；默认尺寸用完整胶囊）。
  Widget _iconWithStatus(
    ExtensionItem e, {
    double size = 24,
    double padding = 8,
    bool dot = false,
  }) {
    final icon = ExtIcon(item: e, size: size, padding: padding);
    final color = _statusColor(e);
    if (!dot || color == null) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -1,
          top: -1,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: SemColors.bg, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _moreButton(
    ExtensionItem e, {
    double size = 30,
    double iconSize = 18,
  }) => Tooltip(
    message: e.builtin ? '详情' : '编辑 / 删除',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _itemMenu(e),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // card 本身带透明度，withValues 会覆盖掉 alpha（深色下变近白）：
          // 先与页面底色合成，得到实底又不发白
          color: Color.alphaBlend(SemColors.card, SemColors.bg),
          border: Border.all(color: SemColors.border),
        ),
        child: Icon(
          Icons.more_horiz,
          size: iconSize,
          color: SemColors.textMuted,
        ),
      ),
    ),
  );

  Widget _card(ExtensionItem e, GridCardSize size, bool editing) {
    final version = e.version.isEmpty ? '' : 'v${e.version}';
    // 眼睛开关只隐藏网址：本地 / 市场来源与版本不是 URL，照旧显示
    final showSource = !_store.hideUrls || e.bundled;
    final showFooter = showSource || version.isNotEmpty;
    final tile = size == GridCardSize.single;
    final bar = size == GridCardSize.wide;
    final tall = size == GridCardSize.tall;

    Widget footer({double fontSize = 10.5}) {
      if (!showFooter) return const SizedBox.shrink();
      return Row(
        children: [
          if (showSource) ...[
            if (!e.bundled) ...[
              Icon(
                Icons.public,
                size: fontSize + 1.5,
                color: SemColors.textMuted,
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                _sourceLabel(e),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize,
                  color: SemColors.textMuted,
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (version.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              version,
              style: TextStyle(fontSize: fontSize, color: SemColors.textMuted),
            ),
          ],
        ],
      );
    }

    if (tile) {
      // 1x1 小方格：**只显示图标**（居中，略放大）。这么小的一格放名字只会被截成
      // 两三个字，图标更好认；名称靠长按选中后顶部尺寸条那一行、或放大后再看。
      return AppCard(
        bottomGap: 0,
        radius: 14,
        padding: EdgeInsets.zero,
        onTap: editing ? null : () => _open(e),
        child: Center(
          child: _iconWithStatus(e, size: 20, padding: 5, dot: true),
        ),
      );
    }

    if (bar) {
      // 1x3 横条：图标在左、名称与简介在右；「更多」靠右上，
      // 给右下角缩放弧线让出位置（这一档卡片只有 59dp 高）
      return AppCard(
        bottomGap: 0,
        radius: 16,
        padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
        onTap: editing ? null : () => _open(e),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _iconWithStatus(e, size: 18, padding: 6, dot: true),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.25,
                      color: SemColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            _moreButton(e, size: 22, iconSize: 14),
          ],
        ),
      );
    }

    if (tall) {
      // 2x2 竖卡：图标 + 更多在顶部一行，名称 / 简介往下排
      return AppCard(
        bottomGap: 0,
        radius: 16,
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        onTap: editing ? null : () => _open(e),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _iconWithStatus(e, size: 17, padding: 6, dot: true),
                const Spacer(),
                _moreButton(e, size: 22, iconSize: 14),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              e.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 3),
            Expanded(
              child: Text(
                e.desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: SemColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 默认 2x3：图标 36 + 标题 + 单行简介 + 来源/版本
    final badge = _badge(e);
    return AppCard(
      bottomGap: 0,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      onTap: editing ? null : () => _open(e),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExtIcon(item: e),
              // 状态胶囊最多见的是「需升级 App」：窄屏上给它可缩的剩余宽度，
              // 宁可整体缩一点，也不要顶出卡片右边。
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: badge == null
                      ? const SizedBox.shrink()
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: badge,
                        ),
                ),
              ),
              const SizedBox(width: 4),
              _moreButton(e),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            e.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 15,
            child: Text(
              e.desc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.25,
                color: SemColors.textSecondary,
              ),
            ),
          ),
          const Spacer(),
          footer(),
        ],
      ),
    );
  }

  Widget _addCard() => SizedBox(
    height: 56,
    child: CustomPaint(
      painter: _DashedBorderPainter(
        color: SemColors.borderStrong.withValues(alpha: 0.55),
      ),
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
                child: Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: SemColors.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '添加拓展',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SemColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 下载失败：把异常包一层再从进度框带回来（失败和结果走同一个返回值）。
class _DownloadFailure {
  const _DownloadFailure(this.error);

  final Object error;
}

/// 不可取消的下载进度框：任务完成 / 失败时自己关掉，并把结果交给调用方。
class _DownloadDialog<T> extends StatefulWidget {
  const _DownloadDialog({required this.label, required this.task});

  final String label;
  final Future<T> Function() task;

  @override
  State<_DownloadDialog<T>> createState() => _DownloadDialogState<T>();
}

class _DownloadDialogState<T> extends State<_DownloadDialog<T>> {
  @override
  void initState() {
    super.initState();
    Future<T>.microtask(widget.task)
        .then((value) {
          if (mounted) Navigator.of(context).pop<Object?>(value);
        })
        .catchError((Object e, StackTrace _) {
          if (mounted) Navigator.of(context).pop<Object?>(_DownloadFailure(e));
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
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(radius),
        ),
      );
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
    // 编辑既有条目一律走 copyWith：市场字段（版本 / 哈希 / 权限 / 来源）不能因为
    // 「在 App 里改了个名字」就丢掉——丢了既看不到更新，权限门也会跟着失效。
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
