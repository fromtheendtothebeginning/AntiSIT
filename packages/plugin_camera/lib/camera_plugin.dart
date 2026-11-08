import 'package:campus_core/campus_core.dart';

import 'camera_capability_impl.dart';

/// 摄像头：给扫码等功能提供实时取景、补光灯与相册识码。
///
/// * **无界面**：不占底栏、不加工具卡片，插件列表里安静地躺着；
/// * **默认开启**：扫码（`plugin_scan`）硬依赖它，关掉摄像头会连带停用扫码；
/// * 硬件与平台相关的能力全部收在本包：`mobile_scanner` / `image_picker` 只在这里
///   出现，消费方只认 campus_core 的 [CameraCapability] 接口。
class CameraPlugin extends FeaturePlugin {
  const CameraPlugin();

  static const pluginId = 'camera';

  @override
  String get id => pluginId;
  @override
  String get name => '摄像头';
  @override
  String get description => '相机取景、补光灯与相册取图识码（无界面，供扫码等功能使用）';
  @override
  bool get defaultEnabled => true;
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_CAMERA=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(
  features: [CameraPlugin()],
  capabilities: {PluginIds.camera: CameraCapabilityImpl()},
);
