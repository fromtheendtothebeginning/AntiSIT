import 'package:campus_core/campus_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 流体云能力的实现：走原生通道 `antisit/fluid_cloud`（见 `android/.../FluidCloud.kt`）。
///
/// 原生侧做三件事：识别系统品牌、发常驻进度通知（Android 16+ 声明 promoted ongoing）、
/// 用 AlarmManager 排「几点亮 / 几点收」——App 被杀掉也按时生效。
class FluidCloudCapabilityImpl implements FluidCloudCapability {
  const FluidCloudCapabilityImpl();

  static const _channel = MethodChannel('antisit/fluid_cloud');

  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  static const _fallback = FluidCloudInfo(
    vendor: 'other',
    label: '本机系统',
    apiLevel: 0,
    notificationsEnabled: false,
    exactAlarm: false,
    promotedSupported: false,
  );

  @override
  Future<FluidCloudInfo> info() async {
    if (!_isAndroid) return _fallback;
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>('info');
      return raw == null ? _fallback : FluidCloudInfo.fromJson(raw);
    } on PlatformException catch (e) {
      debugPrint('[流体云] 读取系统信息失败：$e');
      return _fallback;
    }
  }

  @override
  Future<void> show(FluidCloudWindow window) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('show', window.toJson());
    } on PlatformException catch (e) {
      debugPrint('[流体云] 展示失败：$e');
    }
  }

  @override
  Future<void> dismiss() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('dismiss');
    } on PlatformException catch (e) {
      debugPrint('[流体云] 收起失败：$e');
    }
  }

  @override
  Future<int> schedule(List<FluidCloudWindow> windows) async {
    if (!_isAndroid) return 0;
    try {
      final n = await _channel.invokeMethod<int>('schedule', {
        'windows': [for (final w in windows) w.toJson()],
      });
      return n ?? 0;
    } on PlatformException catch (e) {
      debugPrint('[流体云] 排期失败：$e');
      return 0;
    }
  }

  @override
  Future<void> clear() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('clear');
    } on PlatformException catch (e) {
      debugPrint('[流体云] 清空排期失败：$e');
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException catch (e) {
      debugPrint('[流体云] 申请通知权限失败：$e');
      return false;
    }
  }
}
