import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:campus_core/campus_core.dart';

/// [CameraCapability] 的本机实现：`mobile_scanner` 负责取景与识码，
/// `image_picker` 负责相册取图。
///
/// 只覆盖 Android / iOS：桌面端 [available] 为假，消费方据此降级。
class CameraCapabilityImpl extends CameraCapability {
  const CameraCapabilityImpl();

  static bool get _platformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  bool get available => _platformSupported;

  @override
  CameraSession openSession({
    required ValueChanged<String> onDetected,
    Widget Function(CameraFailure failure)? errorBuilder,
  }) =>
      _ScannerSession(onDetected: onDetected, errorBuilder: errorBuilder);
}

/// 一路相机会话：包住一个 [MobileScannerController]。
class _ScannerSession implements CameraSession {
  _ScannerSession({
    required this.onDetected,
    this.errorBuilder,
  }) : _controller = MobileScannerController(
          formats: const [BarcodeFormat.qrCode], // 只扫二维码：误识别更少、解码更快
          autoZoom: true, // 二维码离得远时自动变焦，远距离扫码也能对上
        );

  final ValueChanged<String> onDetected;
  final Widget Function(CameraFailure failure)? errorBuilder;
  final MobileScannerController _controller;
  final ImagePicker _picker = ImagePicker();
  bool _disposed = false;
  bool _torchOn = false;

  @override
  Widget build(BuildContext context) => MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        errorBuilder: (context, error) =>
            errorBuilder?.call(_failure(error)) ??
            Center(
              child: Text(
                '相机启动失败，请重试',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
      );

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .firstOrNull;
    if (code != null) onDetected(code);
  }

  /// 把相机内核的异常归一成 [CameraFailure]：权限被拒要单独标出来。
  CameraFailure _failure(MobileScannerException error) => CameraFailure(
        message: error.errorDetails?.message ?? error.errorCode.name,
        permissionDenied: error.errorCode == MobileScannerErrorCode.permissionDenied,
      );

  @override
  Future<bool> toggleTorch() async {
    await _controller.toggleTorch();
    _torchOn = !_torchOn;
    return _torchOn;
  }

  @override
  Future<String?> pickImage() async =>
      (await _picker.pickImage(source: ImageSource.gallery))?.path;

  @override
  Future<List<String>> scanImage(String path) async {
    final capture = await _controller.analyzeImage(path);
    return [
      for (final b in capture?.barcodes ?? const <Barcode>[])
        if ((b.rawValue ?? '').trim().isNotEmpty) b.rawValue!.trim(),
    ];
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _controller.dispose();
  }
}
