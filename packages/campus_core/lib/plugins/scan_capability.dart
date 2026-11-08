import 'package:flutter/widgets.dart';

import 'capability.dart';

/// 扫一扫能力：整页打开扫码功能（相机取景 + 相册识码 + 码型分流）。
///
/// 实现方是 `plugin_scan`；入口（第二课堂活动 / 拓展页右上角）只按
/// `PluginRegistry.I.capability<ScanCapability>(PluginIds.scan)` 取用，不 import
/// 扫码插件包。插件没装 / 被停用时取不到能力，入口不显示。
abstract class ScanCapability extends PluginCapability {
  const ScanCapability();

  /// 整页推入扫一扫。
  Future<void> open(BuildContext context);
}
