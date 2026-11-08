import 'dart:async';

import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// 「扫一扫」页（整页推入，入口在第二课堂活动 / 拓展页右上角）。
///
/// 相机取景来自**摄像头插件**（`plugin_camera`，按 [CameraCapability] 取用），
/// 本页只做二维码分流：识出二维码后弹结果面板，内容可复制、网址可直接打开，
/// 关掉面板自动回到取景继续扫。也可以从**相册挑一张图片**识别。
/// 识出**第二课堂活动的签到码**时不走通用面板：给出「完成签到 / 签退」按钮，
/// 由学校接口判定这次算签到还是签退（见 [ScanPage.debugSign] 的正式实现）。
///
/// 扫出的网址用 WebView 内核打开；内核没装 / 被停用时退回系统浏览器。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  /// 二课活动签到二维码：`https://xg.sit.edu.cn/hdgl/hdxq/qd/:hdId/:hdActId/:时间戳`
  /// （签退形态是同路由的 qt 变体，学校同一个接口 signInOrSignOut 按状态判定方向）。
  static final RegExp dektSignRe =
      RegExp(r'^https://xg\.sit\.edu\.cn/hdgl/hdxq/(?:qd|qt)/([\w-]+)/([\w-]+)/(?:\d{13})$');

  /// 二课**报名（培训）二维码**：`…/hdgl/pxqd/:hdId/:pxId`——无时间戳、只有两段，
  /// 提交走另一个接口（shsj/qd.zf，单向签到没有签退）。
  static final RegExp dektTrainSignRe =
      RegExp(r'^https://xg\.sit\.edu\.cn/hdgl/pxqd/([\w-]+)/([\w-]+)$');

  /// 二课**活动详情码**（海报 / 详情页二维码，报名用）：
  /// 门户包装形态 `…/login?redirect=/hdgl/hdxq/:hdId`，或裸 `…/hdgl/hdxq/:hdId`。
  /// 扫到后直接用 App 自己的活动详情页打开（详情 + 报名都在里面）。
  static String? dektDetailId(String code) {
    final u = Uri.tryParse(code.trim());
    if (u == null || u.host != 'xg.sit.edu.cn') return null;
    var path = u.path;
    if (path == '/login') {
      // 生成端可能整段百分号编码，queryParameters 解一层后按需再解一层
      final r = u.queryParameters['redirect'];
      if (r == null) return null;
      path = r.startsWith('/hdgl/') ? r : Uri.decodeComponent(r);
    }
    final m = RegExp(r'^/hdgl/hdxq/([\w-]+)$').firstMatch(path);
    return m?.group(1);
  }

  /// 测试注入点：替身「相机」组件——widget 测试没有平台通道，真 MobileScanner
  /// 起不来。null = 用真相机。
  @visibleForTesting
  static Widget Function(BuildContext context)? debugCamera;

  /// 测试注入点：替身「选图片」（不弹系统相册）。
  @visibleForTesting
  static Future<String?> Function()? debugPickImage;

  /// 测试注入点：替身「图片识别」（不跑真条码识别），返回识出的码值列表。
  @visibleForTesting
  static Future<List<String>> Function(String path)? debugAnalyzeImage;

  /// 测试注入点：替身「签到提交」（不跑直连登录）。
  /// 正式实现走 `CampusDirect.I.activitySignInOrSignOut`（直连学工系统）。
  @visibleForTesting
  static Future<Map<String, dynamic>> Function(String hdId, String hdActId)? debugSign;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  /// 相机会话：摄像头插件没装 / 被停用、或平台不支持时为 null（页面给提示）。
  CameraSession? _session;

  /// 面板开着时识到的码：期间不再识别（防同一枚码反复弹面板）。
  String? _pausedValue;

  /// 相册图识别中（按钮转圈、防重入）。
  bool _picking = false;

  /// 手电筒开关状态（仅用于按钮显示；实际状态以相机会话为准）。
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    if (ScanPage.debugCamera != null) return; // 测试替身：不碰平台通道
    final camera = PluginRegistry.I.capability<CameraCapability>(PluginIds.camera);
    if (camera != null && camera.available) {
      _session = camera.openSession(
        onDetected: _onCode,
        errorBuilder: _cameraError,
      );
    }
  }

  @override
  void dispose() {
    final session = _session;
    if (session != null) unawaited(session.dispose());
    super.dispose();
  }

  /// 门户包装形态：`https://xg.sit.edu.cn/login?redirect=/hdgl/…` → 内部完整地址。
  /// 生成端可能把 redirect 整段百分号编码；不是包装形态返回 null。
  @visibleForTesting
  static String? unwrapLoginRedirect(String code) {
    final u = Uri.tryParse(code.trim());
    if (u == null || u.host != 'xg.sit.edu.cn' || u.path != '/login') return null;
    final r = u.queryParameters['redirect'];
    if (r == null || !r.startsWith('/hdgl/')) return null;
    return 'https://xg.sit.edu.cn$r';
  }

  /// 一枚码被识出后的统一入口（相机流 / 相册 / 测试注入共用）：
  /// 面板开着就忽略，同一枚码不会把面板叠起来。
  @visibleForTesting
  Future<void> debugDetect(String value) => _onCode(value);

  Future<void> _onCode(String code) async {
    if (_pausedValue != null) return;
    // 门户包装（/login?redirect=…）先拆出内部地址，再按码型匹配
    final effective = unwrapLoginRedirect(code) ?? code;
    // 二课活动的签到码：走专门的签到面板（学校接口判定本次是签到还是签退）
    final sign = ScanPage.dektSignRe.firstMatch(effective);
    if (sign != null) {
      await _signFlow(hdId: sign.group(1)!, hdActId: sign.group(2)!, raw: code);
      return;
    }
    // 二课活动的报名（培训）码：另一个接口，单向签到
    final train = ScanPage.dektTrainSignRe.firstMatch(effective);
    if (train != null) {
      await _signFlow(hdId: train.group(1)!, hdActId: train.group(2)!,
          raw: code, train: true);
      return;
    }
    // 二课活动的详情码（报名用）：用 App 自己的活动详情页打开。
    // 活动插件没装 / 被停用时退化成普通网址（下面的通用面板），别让面板打不开。
    final detailId = ScanPage.dektDetailId(effective);
    final activities =
        PluginRegistry.I.capability<ActivitiesCapability>(PluginIds.activities);
    if (detailId != null && activities != null) {
      await _detailFlow(hdId: detailId, raw: code, activities: activities);
      return;
    }
    setState(() => _pausedValue = code);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _ResultSheet(
        code: code,
        onOpen: () {
          Navigator.pop(ctx);
          _openScannedLink(context, code);
        },
      ),
    );
    if (!mounted) return;
    setState(() => _pausedValue = null); // 面板关了（继续扫 / 下滑），回到取景
  }

  /// 扫出的网址在本机 WebView 内核里整页打开（应用内浏览器）；
  /// 内核不可用（WebView 插件被停用 / 剔除）时退回系统浏览器。
  Future<void> _openScannedLink(BuildContext context, String url) async {
    final webview = PluginRegistry.I.capability<WebViewCapability>(PluginIds.webview);
    if (webview != null && webview.available) {
      await webview.openPage(context, url: url, title: Uri.tryParse(url)?.host ?? '');
      return;
    }
    await _openExternalUrl(context, url);
  }

  /// 二课签到流程：弹签到面板，提交经学工系统（学校返回判定原文）。
  /// [train] = 报名（培训）码：另一个接口、单向签到。
  Future<void> _signFlow(
      {required String hdId, required String hdActId, required String raw,
      bool train = false}) async {
    setState(() => _pausedValue = raw);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _SignSheet(
        hdId: hdId,
        hdActId: hdActId,
        raw: raw,
        train: train,
        submit: () async {
          final fake = ScanPage.debugSign;
          final r = fake != null
              ? await fake(hdId, hdActId)
              : train
                  ? await ApiClient.I.activityTrainingSignIn(hdId, hdActId)
                  : await ApiClient.I.activitySignInOrSignOut(hdId, hdActId);
          return ((r['data'] as Map?)?['msg'] ?? '').toString();
        },
      ),
    );
    if (!mounted) return;
    setState(() => _pausedValue = null); // 面板关了，回到取景继续扫
  }

  /// 二课活动详情码（报名用）：关掉面板，用 App 自己的活动详情页打开——
  /// 活动介绍、时间地点、报名按钮都在详情页里，报名复用既有双模式流程。
  /// 详情接口只回说明，名称 / 时间 / 名额等元信息在活动列表里：面板开着就先按
  /// hdId 捞出来，进详情页时带上，别让页面开天窗。
  /// 详情页由活动插件提供（[ActivitiesCapability]），本插件不 import 它。
  Future<void> _detailFlow({
    required String hdId,
    required String raw,
    required ActivitiesCapability activities,
  }) async {
    setState(() => _pausedValue = raw);
    final metaFuture = _fetchActivityMeta(hdId);
    final opened = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => _DetailSheet(
        raw: raw,
        onOpen: () async {
          Navigator.pop(ctx, true);
          final meta = await metaFuture;
          if (!mounted) return;
          await activities.openDetail(context, id: hdId, activity: meta);
          if (mounted) setState(() => _pausedValue = null); // 详情页退出，恢复扫码
        },
      ),
    );
    if (!mounted) return;
    if (opened != true) {
      setState(() => _pausedValue = null); // 「继续扫码」关的：回到取景
    }
  }

  /// 按 hdId 从活动列表里捞元信息（双模式：直连走学工列表，服务器走隧道）；
  /// 拉不到 / 列表里没有这条活动时返回 null（详情页靠说明兜底，照样能报名）。
  Future<Map<String, dynamic>?> _fetchActivityMeta(String hdId) async {
    try {
      final r = await ApiClient.I.activities();
      final items = ((r['data']?['activities'] ?? r['activities']) as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      for (final a in items) {
        if ('${a['id']}' == hdId) return a;
      }
    } catch (_) {} // 列表拉不到：详情页靠说明兜底
    return null;
  }

  /// 相册挑一张图片 → 条码识别。没挑（用户取消）静默返回；识别不出给一句提示。
  Future<void> _pickAndAnalyze() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final fakePick = ScanPage.debugPickImage;
      final path = fakePick != null
          ? await fakePick()
          : await _session?.pickImage();
      if (path == null || !mounted) return;
      final fakeAnalyze = ScanPage.debugAnalyzeImage;
      final codes = fakeAnalyze != null
          ? await fakeAnalyze(path)
          : (await _session?.scanImage(path)) ?? const <String>[];
      if (!mounted) return;
      if (codes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('这张图片里没识别出二维码'),
            behavior: SnackBarBehavior.floating));
        return;
      }
      // 一张图里可能有好几个码（比如海报上签到 / 签退并排）：去重后
      // 多于一个就弹选择面板让用户挑，挑完走与单码一致的识别链。
      final unique = codes.toSet().toList();
      if (unique.length > 1) {
        // 识别到此为止（选择不算识别）：按钮停转，不然测试的 settle 也会被它挂住
        if (mounted) setState(() => _picking = false);
        final picked = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => _CodePickerSheet(codes: unique),
        );
        if (!mounted || picked == null) return;
        unawaited(_onCode(picked));
        return;
      }
      // 面板自己管生命周期：等它关掉的话按钮会一直停在「识别中」转圈
      unawaited(_onCode(unique.single));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('图片识别失败，换一张试试'),
            behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 摄像头插件不可用时页面只留一句提示，底部按钮也不再给（按了也没反应）
    final cameraReady = ScanPage.debugCamera != null || _session != null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 相机取景来自摄像头插件（测试环境用替身）
          Positioned.fill(
            child: ScanPage.debugCamera?.call(context) ??
                _session?.build(context) ??
                _cameraUnavailable(context),
          ),
          // 取景框 + 提示
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _ScanWindow(),
                const SizedBox(height: 16),
                const Text('对准二维码，自动识别',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          // 关页
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 12,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              tooltip: '收起扫一扫',
            ),
          ),
          // 底部操作条：手电筒 + 相册识别，实心大按钮一眼能找到
          if (cameraReady)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 手电筒是真相机会话才有的能力（测试替身没有）
                  if (_session != null) ...[
                    _BigActionButton(
                      icon: _torchOn
                          ? Icons.flashlight_on_rounded
                          : Icons.flashlight_off_rounded,
                      label: _torchOn ? '关灯' : '手电筒',
                      onPressed: _toggleTorch,
                    ),
                    const SizedBox(width: 28),
                  ],
                  _BigActionButton(
                    icon: _picking ? null : Icons.photo_library_rounded,
                    busy: _picking,
                    label: _picking ? '识别中…' : '相册识别',
                    filled: true,
                    onPressed: _picking ? null : _pickAndAnalyze,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 手电筒：暗光会场（签到现场常见）直接影响识别率。
  Future<void> _toggleTorch() async {
    final session = _session;
    if (session == null) return;
    try {
      final on = await session.toggleTorch();
      if (mounted) setState(() => _torchOn = on);
    } catch (_) {}
  }

  /// 相机起不来（权限被拒最常见）：给条人话和出路。
  Widget _cameraError(CameraFailure failure) {
    final denied = failure.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white54, size: 40),
            const SizedBox(height: 12),
            Text(
              denied ? '需要相机权限：请在系统设置里允许 AntiSIT 使用相机' : '相机启动失败，请重试',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  /// 摄像头插件不可用（没装 / 被停用 / 平台不支持）：别让相机区域开天窗。
  Widget _cameraUnavailable(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: Colors.white54, size: 40),
              const SizedBox(height: 12),
              const Text(
                '摄像头不可用：请在「我的 → 插件管理」里启用「摄像头」插件',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
}

/// 打开外部链接；失败（没有浏览器 / 平台不支持）则复制链接并提示。
/// WebView 内核被停用时扫出的网址走这里（与更新弹窗同一套兜底）。
Future<void> _openExternalUrl(BuildContext context, String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已复制链接，可粘贴到浏览器打开'),
        behavior: SnackBarBehavior.floating));
  }
}

/// 取景框：圆角白框，中间透出相机画面。
class _ScanWindow extends StatelessWidget {
  const _ScanWindow();

  @override
  Widget build(BuildContext context) => Container(
        width: 232,
        height: 232,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white70, width: 2),
        ),
      );
}

/// 扫码页底部的大按钮：实心（主操作）/ 描边（次操作）两态，深色取景上一眼能找到。
class _BigActionButton extends StatelessWidget {
  const _BigActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = false,
    this.busy = false,
  });

  final IconData? icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bg = filled ? Colors.white : Colors.black.withValues(alpha: 0.55);
    final fg = filled ? Colors.black87 : Colors.white;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white38),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
            else if (icon != null)
              Icon(icon, size: 22, color: fg),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// 多码选择面板：一张图片识出多个二维码时让用户挑一个，
/// 挑完走与单码一致的识别链（签到 / 详情 / 通用结果按码型自动分流）。
class _CodePickerSheet extends StatelessWidget {
  const _CodePickerSheet({required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('识别到 ${codes.length} 个二维码，点选要用的一个',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: onSurface)),
            const SizedBox(height: 4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in codes)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.qr_code_2_rounded, size: 20),
                      title: Text(c,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, color: onSurface)),
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 二课签到面板：签到 / 签退码由学校按场次判定方向，报名码单向签到；
/// 按钮点下去把学校的判定原文（成功原因 / 失败原因）摆给用户看。
class _SignSheet extends StatefulWidget {
  const _SignSheet({
    required this.hdId,
    required this.hdActId,
    required this.raw,
    required this.submit,
    this.train = false,
  });

  final String hdId;
  final String hdActId;

  /// 原始二维码内容（复制 / 出问题时用户自己能核对）。
  final String raw;

  /// 报名（培训）码：另一个接口、单向签到，没有「签退」语义。
  final bool train;

  /// 提交签到，成功返回学校提示原文；失败抛 ApiError（学校原文）。
  final Future<String> Function() submit;

  @override
  State<_SignSheet> createState() => _SignSheetState();
}

class _SignSheetState extends State<_SignSheet> {
  bool _busy = false;
  String? _ok;
  String? _err;

  Future<void> _go() async {
    if (_busy || _ok != null) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final msg = await widget.submit();
      if (mounted) setState(() => _ok = msg.isEmpty ? '完成' : msg);
    } catch (e) {
      if (mounted) {
        setState(() => _err = e is ApiError ? e.message : '签到失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.train ? '第二课堂 · 报名签到' : '第二课堂 · 扫码签到',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: onSurface)),
            const SizedBox(height: 8),
            Text(
              _ok != null
                  ? '$_ok'
                  : (_err ??
                      (widget.train
                          ? '扫到的是第二课堂活动的报名（培训）签到码，点下方按钮完成签到。'
                          : '扫到的是第二课堂活动的签到码，点下方按钮提交，'
                              '由学校判定本次算签到还是签退。')),
              style: TextStyle(
                  fontSize: 14, height: 1.6,
                  color: _err != null ? SemColors.danger : onSurface),
            ),
            if (_ok == null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _go,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: _busy
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.how_to_reg_outlined, size: 20),
                label: Text(_busy ? '提交中…' : (widget.train ? '完成签到' : '完成签到 / 签退'),
                    style: const TextStyle(fontSize: 15)),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.raw));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('已复制码内容'),
                        behavior: SnackBarBehavior.floating));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('复制码内容'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('继续扫码'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 扫码结果面板：内容可选可复制，网址直接打开，「继续扫码」关面板回取景。
/// 二课活动详情码面板：这个码指向活动详情页（报名入口在详情页里），
/// 引导用户进 App 自己的活动详情页，而不是把学校登录页甩给浏览器。
class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.raw, required this.onOpen});

  final String raw;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('第二课堂 · 活动码',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: onSurface)),
            const SizedBox(height: 8),
            Text('扫到的是第二课堂活动的详情码：点下方按钮查看活动介绍并报名，'
                '报名状态与提交都在 App 内完成。',
                style: TextStyle(fontSize: 14, height: 1.6, color: onSurface)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onOpen,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.event_note_outlined, size: 20),
              label: const Text('查看活动详情', style: TextStyle(fontSize: 15)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: raw));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('已复制码内容'),
                        behavior: SnackBarBehavior.floating));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('复制码内容'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('继续扫码'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultSheet extends StatelessWidget {
  const _ResultSheet({required this.code, required this.onOpen});

  final String code;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(code);
    final isUrl = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('扫码结果',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 10),
            SelectableText(code,
                style: TextStyle(
                    fontSize: 14, height: 1.5,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('已复制'),
                        behavior: SnackBarBehavior.floating));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('复制'),
                ),
                if (isUrl)
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('打开链接'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('继续扫码'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
