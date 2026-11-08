import 'package:campus_core/campus_core.dart';

import 'scan_capability_impl.dart';

/// 扫一扫：相机取景 / 相册识码 + 二课码型分流。
///
/// * **硬依赖摄像头**（[dependencies]）：取景、补光灯、图片识码都由 `plugin_camera`
///   提供；启用本插件会连带启用摄像头，停用摄像头会连带停用本插件。
/// * **软关联 WebView 内核**（[optionalDependencies]）：扫出的网址优先用内核整页
///   打开；内核没装 / 被停用时退回系统浏览器，扫码本身不受影响。
/// * **软关联二课活动**：活动详情码要打开 App 的活动详情页；活动插件不在时，
///   这类码退化成普通网址处理。
/// * **无界面贡献**：入口是第二课堂活动 / 拓展页右上角的扫码图标，不占底栏 /
///   工具宫格；别的插件按 [ScanCapability] 能力取用，不 import 本包。
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

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_SCAN=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(
  features: [ScanPlugin()],
  capabilities: {PluginIds.scan: ScanCapabilityImpl()},
);
