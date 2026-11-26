import 'package:campus_core/campus_core.dart';

import 'fluid_cloud_capability_impl.dart';

/// 流体云：把一条常驻进度通知交给系统展示。
/// 各家流体云 / 原子通知 / 焦点通知都不需厂商 SDK：发 ongoing + 进度的通知即可，
/// Android 16+ 再声明 promoted ongoing，由系统决定是否升格；本插件只提供能力。
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

/// 插件包入口：tool/gen_plugins.dart 按包名登记；能力挂在 PluginIds.fluidCloud 上，
/// 课程通知插件按 id 取用，停用后取不到则退回系统通知；EXCLUDE_FLUID_CLOUD 为真时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(
  features: [FluidCloudPlugin()],
  capabilities: {PluginIds.fluidCloud: FluidCloudCapabilityImpl()},
);
