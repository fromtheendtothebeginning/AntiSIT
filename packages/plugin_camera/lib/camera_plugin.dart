import 'package:campus_core/campus_core.dart';

import 'camera_capability_impl.dart';

/// 摄像头：提供实时取景、补光灯与相册识码，无界面、不占底栏。
/// 默认开启：扫码插件硬依赖它，关掉会连带停用扫码；硬件相关实现只在本包内。
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

/// 插件包入口：tool/gen_plugins.dart 按包名登记；--dart-define=EXCLUDE_CAMERA=true 时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(
  features: [CameraPlugin()],
  capabilities: {PluginIds.camera: CameraCapabilityImpl()},
);
