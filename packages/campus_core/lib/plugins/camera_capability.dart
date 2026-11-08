import 'package:flutter/widgets.dart';

import 'capability.dart';

/// 相机能力：给扫码等需要实时取景 / 识码的功能用。
///
/// 实现方是 `plugin_camera`（`mobile_scanner` + `image_picker`）；消费方只认这个
/// 接口，按 `PluginRegistry.I.capability<CameraCapability>(PluginIds.camera)` 取用，
/// 不 import 相机插件包。提供方没装 / 被停用时返回 null，消费方据此降级。
abstract class CameraCapability extends PluginCapability {
  const CameraCapability();

  /// 当前平台能不能用（相机内核覆盖 Android / iOS）。
  bool get available;

  /// 开一路相机会话。会话持有相机控制器，用完必须 [CameraSession.dispose]。
  /// [onDetected] 收到的是去掉首尾空白后的二维码原文。
  CameraSession openSession({
    required ValueChanged<String> onDetected,
    Widget Function(CameraFailure failure)? errorBuilder,
  });
}

/// 一路相机会话：实时取景 + 补光灯 + 相册取图 / 图片识码。
abstract class CameraSession {
  /// 铺满父容器的取景画面；相机出错时交给 [CameraCapability.openSession] 的
  /// errorBuilder 渲染，没给就显示一句通用提示。
  Widget build(BuildContext context);

  /// 切换补光灯，返回切换后的状态（开 / 关）。
  Future<bool> toggleTorch();

  /// 从相册挑一张图，返回本机路径；用户取消返回 null。
  Future<String?> pickImage();

  /// 识别一张图片里的二维码，返回去空白后的文本（可能有多枚）。
  Future<List<String>> scanImage(String path);

  /// 释放相机与控制器。之后再调用其它方法没有意义。
  Future<void> dispose();
}

/// 相机失败的归一结果：权限被拒单独标出来，页面才能给「去设置」的提示。
class CameraFailure {
  const CameraFailure({required this.message, this.permissionDenied = false});

  final String message;
  final bool permissionDenied;
}
