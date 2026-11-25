import 'dart:async';

import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'scan_codes.dart';
import 'scan_sheets.dart';

/// 「扫一扫」页：相机取景来自摄像头插件（按 [CameraCapability] 取用），本页只做二维码分流。
/// 二课签到码走签到面板；[ScanMode.addExtension] 下的安装码交回拓展页处理。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, this.mode = ScanMode.generic});

  /// 扫码用途（见 [ScanMode]）：普通扫一扫 / 给拓展页加内容。
  final ScanMode mode;

  /// 拓展安装码 → 扫码结果；只认 https + 64 位十六进制 sha256 的格式。
  @visibleForTesting
  static ScanOutcome? extensionOutcome(String code) => extensionOutcomeOf(code);

  /// 像安装码但字段可能不合法（用于给出「格式不对」而不是闷头当普通文本）。
  static bool looksLikeExtensionCode(String code) =>
      looksLikeExtensionCodeOf(code);

  /// 二课活动签到二维码：`https://xg.sit.edu.cn/hdgl/hdxq/(qd|qt)/:hdId/:hdActId/:时间戳`。
  /// 签到与签退同一路由，方向由学校接口按状态判定。
  static final RegExp dektSignRe =
      RegExp(r'^https://xg\.sit\.edu\.cn/hdgl/hdxq/(?:qd|qt)/([\w-]+)/([\w-]+)/(?:\d{13})$');

  /// 二课报名（培训）二维码：`…/hdgl/pxqd/:hdId/:pxId`，另一个接口、单向签到。
  static final RegExp dektTrainSignRe =
      RegExp(r'^https://xg\.sit\.edu\.cn/hdgl/pxqd/([\w-]+)/([\w-]+)$');

  /// 二课活动详情码 → hdId（门户 `/login?redirect=…` 包装也认）。
  static String? dektDetailId(String code) => dektDetailIdOf(code);

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

  /// 一枚码被识出后的统一入口（相机流 / 相册 / 测试注入共用）。
  @visibleForTesting
  Future<void> debugDetect(String value) => _onCode(value);

  /// 按码型分流：拓展安装码 / 签到码 / 活动详情码 / 普通文本。
  Future<void> _onCode(String code) async {
    if (_pausedValue != null) return;
    // 从「拓展」页进来的：只判拓展安装码 / 普通网址，确认后关页把结果带回去
    if (widget.mode == ScanMode.addExtension) {
      final outcome = ScanPage.extensionOutcome(code);
      if (outcome != null) {
        await _extensionFlow(outcome);
        return;
      }
      if (ScanPage.looksLikeExtensionCode(code)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              content: Text('拓展安装码格式不对：需要 https 下载地址和 64 位 sha256'),
              behavior: SnackBarBehavior.floating));
        return;
      }
    }
    // 门户包装（/login?redirect=…）先拆出内部地址，再按码型匹配
    final effective = unwrapLoginRedirect(code) ?? code;
    final sign = ScanPage.dektSignRe.firstMatch(effective);
    if (sign != null) {
      await _signFlow(hdId: sign.group(1)!, hdActId: sign.group(2)!, raw: code);
      return;
    }
    final train = ScanPage.dektTrainSignRe.firstMatch(effective);
    if (train != null) {
      await _signFlow(hdId: train.group(1)!, hdActId: train.group(2)!,
          raw: code, train: true);
      return;
    }
    // 活动插件没装 / 被停用时退化成普通网址，别让面板打不开
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
      builder: (ctx) => ScanResultSheet(
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

  /// 扫出的网址在应用内浏览器打开；WebView 内核不可用时退回系统浏览器。
  Future<void> _openScannedLink(BuildContext context, String url) async {
    final webview = PluginRegistry.I.capability<WebViewCapability>(PluginIds.webview);
    if (webview != null && webview.available) {
      await webview.openPage(context, url: url, title: Uri.tryParse(url)?.host ?? '');
      return;
    }
    await _openExternalUrl(context, url);
  }

  /// 拓展模式的结果面板：确认后关掉扫码页，把 [ScanOutcome] 交给调用方（拓展页）。
  Future<void> _extensionFlow(ScanOutcome outcome) async {
    setState(() => _pausedValue = outcome.raw);
    final picked = await showModalBottomSheet<ScanOutcome>(
      context: context,
      builder: (ctx) => ScanExtensionSheet(outcome: outcome),
    );
    if (!mounted) return;
    if (picked != null) {
      Navigator.of(context).pop(picked);
      return;
    }
    setState(() => _pausedValue = null); // 面板关了，回到取景继续扫
  }

  /// 二课签到流程：提交经学工系统（学校返回判定原文）。
  /// [train] = 报名（培训）码：另一个接口、单向签到。
  Future<void> _signFlow(
      {required String hdId, required String hdActId, required String raw,
      bool train = false}) async {
    setState(() => _pausedValue = raw);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => ScanSignSheet(
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

  /// 二课活动详情码：关掉面板，用 App 自己的活动详情页打开。
  /// 详情接口只回说明，名称 / 时间 / 名额等元信息先按 hdId 从活动列表捞出带上。
  Future<void> _detailFlow({
    required String hdId,
    required String raw,
    required ActivitiesCapability activities,
  }) async {
    setState(() => _pausedValue = raw);
    final metaFuture = _fetchActivityMeta(hdId);
    final opened = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => ScanDetailSheet(
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

  /// 按 hdId 从活动列表里捞元信息；拉不到 / 列表里没有这条活动时返回 null。
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
      // 一张图里可能有好几个码：去重后多于一个就弹选择面板，挑完走同一条识别链
      final unique = codes.toSet().toList();
      if (unique.length > 1) {
        // 识别到此为止（选择不算识别）：按钮停转，不然测试的 settle 也会被它挂住
        if (mounted) setState(() => _picking = false);
        final picked = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => ScanCodePickerSheet(codes: unique),
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
                const ScanWindow(),
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
          // 底部操作条：手电筒 + 相册识别
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
                    ScanBigActionButton(
                      icon: _torchOn
                          ? Icons.flashlight_on_rounded
                          : Icons.flashlight_off_rounded,
                      label: _torchOn ? '关灯' : '手电筒',
                      onPressed: _toggleTorch,
                    ),
                    const SizedBox(width: 28),
                  ],
                  ScanBigActionButton(
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
