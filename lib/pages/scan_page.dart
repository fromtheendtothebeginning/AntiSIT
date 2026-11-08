import 'dart:async';

import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../widgets/update_dialog.dart' show openExternalUrl;

/// 「扫一扫」页（整页推入，入口在第二课堂活动 / 拓展页右上角）。
///
/// 摄像头实时取景 + 取景框；识出二维码后弹结果面板：内容可复制，网址可直接打开，
/// 关掉面板自动回到取景继续扫。也可以从**相册挑一张图片**识别。
/// 识出**第二课堂活动的签到码**时不走通用面板：给出「完成签到 / 签退」按钮，
/// 由学校接口判定这次算签到还是签退（见 [ScanPage.debugSign] 的正式实现）。
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
  /// 相机控制器：惰性创建——测试替身（debugCamera）模式下不碰平台通道。
  MobileScannerController? _controller;

  /// 面板开着时识到的码：期间不再识别（防同一枚码反复弹面板）。
  String? _pausedValue;

  /// 相册图识别中（按钮转圈、防重入）。
  bool _picking = false;

  /// 手电筒开关状态（仅用于按钮显示；实际状态以控制器为准）。
  bool _torchOn = false;

  MobileScannerController get _cam => _controller ??= MobileScannerController(
        formats: [BarcodeFormat.qrCode], // 只扫二维码：误识别更少、解码更快
        autoZoom: true, // 二维码离得远时自动变焦，远距离扫码也能对上
      );

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// 一枚码被识出后的统一入口（相机流 / 相册 / 测试注入共用）：
  /// 面板开着就忽略，同一枚码不会把面板叠起来。
  @visibleForTesting
  Future<void> debugDetect(String value) => _onCode(value);

  Future<void> _onCode(String code) async {
    if (_pausedValue != null) return;
    // 二课活动的签到码：走专门的签到面板（学校接口判定本次是签到还是签退）
    final sign = ScanPage.dektSignRe.firstMatch(code);
    if (sign != null) {
      await _signFlow(hdId: sign.group(1)!, hdActId: sign.group(2)!, raw: code);
      return;
    }
    // 二课活动的报名（培训）码：另一个接口，单向签到
    final train = ScanPage.dektTrainSignRe.firstMatch(code);
    if (train != null) {
      await _signFlow(hdId: train.group(1)!, hdActId: train.group(2)!,
          raw: code, train: true);
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
  /// 内核不可用（WebView 插件被停用 / 剔除 / 未注入）时退回系统浏览器。
  Future<void> _openScannedLink(BuildContext context, String url) async {
    final webview = PluginRegistry.I.capability<WebViewCapability>(PluginIds.webview);
    if (webview != null && webview.available) {
      await webview.openPage(context, url: url, title: Uri.tryParse(url)?.host ?? '');
      return;
    }
    await openExternalUrl(context, url);
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

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .firstOrNull;
    if (code == null) return;
    _onCode(code);
  }

  /// 相册挑一张图片 → 条码识别。没挑（用户取消）静默返回；识别不出给一句提示。
  Future<void> _pickAndAnalyze() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final fakePick = ScanPage.debugPickImage;
      final path = fakePick != null
          ? await fakePick()
          : (await ImagePicker().pickImage(source: ImageSource.gallery))?.path;
      if (path == null || !mounted) return;
      final codes = await (ScanPage.debugAnalyzeImage?.call(path) ??
          _analyzeImage(path));
      if (!mounted) return;
      if (codes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('这张图片里没识别出二维码'),
            behavior: SnackBarBehavior.floating));
        return;
      }
      // 面板自己管生命周期：等它关掉的话按钮会一直停在「识别中」转圈
      unawaited(_onCode(codes.first));
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

  Future<List<String>> _analyzeImage(String path) async {
    final capture = await _cam.analyzeImage(path);
    return [
      for (final b in capture?.barcodes ?? const <Barcode>[])
        if ((b.rawValue ?? '').trim().isNotEmpty) b.rawValue!.trim(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 相机取景（测试环境用替身）
          Positioned.fill(
            child: ScanPage.debugCamera?.call(context) ??
                MobileScanner(
                  controller: _cam,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => _cameraError(error),
                ),
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
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.paddingOf(context).bottom + 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _BigActionButton(
                  icon: _torchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                  label: _torchOn ? '关灯' : '手电筒',
                  onPressed: _toggleTorch,
                ),
                const SizedBox(width: 28),
                _BigActionButton(
                  icon: _picking
                      ? null
                      : Icons.photo_library_rounded,
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
    try {
      await _cam.toggleTorch();
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {}
  }

  /// 相机起不来（权限被拒最常见）：给条人话和出路。
  Widget _cameraError(Object error) {
    final denied = error is MobileScannerException &&
        error.errorCode == MobileScannerErrorCode.permissionDenied;
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
