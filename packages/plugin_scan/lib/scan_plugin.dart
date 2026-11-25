import 'package:campus_core/campus_core.dart';

import 'scan_capability_impl.dart';

/// 扫一扫：相机取景 / 相册识码 + 二课码型分流。
/// 硬依赖摄像头、软关联 WebView 与二课活动；无界面贡献，别的插件按 [ScanCapability] 取用。
class ScanPlugin extends FeaturePlugin {
  const ScanPlugin();

  static const pluginId = 'scan';

  @override
  String get id => pluginId;
  @override
  String get name => '扫一扫';
  @override
  String get description => '相机取景与相册识码；二课签到码一键提交，扫出的网址用内置浏览器打开';
  @override
  List<String> get dependencies => const [PluginIds.camera];
  @override
  List<String> get optionalDependencies =>
      const [PluginIds.webview, PluginIds.activities];
  @override
  bool get defaultEnabled => true;
}

/// 插件包入口：清单生成器按包名登记；EXCLUDE_SCAN 开关为真时整包被摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(
  features: [ScanPlugin()],
  capabilities: {PluginIds.scan: ScanCapabilityImpl()},
);
