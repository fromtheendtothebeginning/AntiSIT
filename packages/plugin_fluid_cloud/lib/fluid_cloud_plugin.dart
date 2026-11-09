import 'package:campus_core/campus_core.dart';

import 'fluid_cloud_capability_impl.dart';

/// 流体云：把一条「常驻进度通知」交给系统展示。
///
/// ColorOS 流体云 / OriginOS 原子通知 / 澎湃OS 焦点通知都**不需要厂商 SDK**：
/// 按系统通知规范发一条 ongoing + 进度的通知，Android 16+ 再声明 promoted ongoing，
/// 由系统决定是否升格成各自的流体云形态；更早的系统就是一条常驻倒计时通知。
///
/// 本插件只提供能力（[FluidCloudCapability]），具体展示什么由「流体云课程通知」决定。
class FluidCloudPlugin extends FeaturePlugin {
  const FluidCloudPlugin();

  static const pluginId = PluginIds.fluidCloud;

  @override
  String get id => pluginId;
  @override
  String get name => '流体云';
  @override
  String get description => '常驻课程通知交给流体云 / 原子通知 / 焦点通知展示（系统通知 API，无需厂商 SDK）';
  @override
  bool get defaultEnabled => true;
  @override
  int get settingsOrder => 46;
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 能力挂在本插件 id 上：课程通知插件按「接口 + id」取用，不 import 本包；
/// 停用 / 删除后取不到能力，课程通知插件会退回系统通知。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_FLUID_CLOUD=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(
  features: [FluidCloudPlugin()],
  capabilities: {PluginIds.fluidCloud: FluidCloudCapabilityImpl()},
);
