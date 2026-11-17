import 'package:flutter/widgets.dart';

import 'capability.dart';

/// 扫一扫的用途。
enum ScanMode {
  /// 普通扫码：二课签到 / 活动详情 / 网址，直接在扫码页里处理。
  generic,

  /// 给「拓展」页加东西：识别拓展安装码或普通网址，把结果交回调用方
  /// （由调用方决定下载安装 / 加一条 web 拓展，扫码插件不碰拓展逻辑）。
  addExtension,
}

/// 拓展模式下的扫码结果。
sealed class ScanOutcome {
  const ScanOutcome(this.raw);

  /// 二维码原文（复制 / 调试用）。
  final String raw;
}

/// 普通 http(s) 网址：调用方可以把它作为 web 拓展加进去。
class ScanLinkOutcome extends ScanOutcome {
  const ScanLinkOutcome({required this.url, required String raw}) : super(raw);

  final String url;
}

/// 拓展安装码：`{"antisit":"ext","url":"https://…/x.zip","sha256":"64 位十六进制"}`。
/// 调用方负责下载、校验 sha256、解压安装。
class ScanBundleOutcome extends ScanOutcome {
  const ScanBundleOutcome({
    required this.url,
    required this.sha256,
    this.name,
    this.id,
    required String raw,
  }) : super(raw);

  final String url;

  /// 小写 64 位十六进制；下载到的字节必须与它一致，否则不能装。
  final String sha256;

  /// 码里可选的展示名 / id（最终以包里的 ext.json 为准）。
  final String? name;
  final String? id;
}

/// 扫一扫能力：整页打开扫码功能（相机取景 + 相册识码 + 码型分流）。
///
/// 实现方是 `plugin_scan`；入口（第二课堂活动 / 拓展页右上角）只按
/// `PluginRegistry.I.capability<ScanCapability>(PluginIds.scan)` 取用，不 import
/// 扫码插件包。插件没装 / 被停用时取不到能力，入口不显示。
abstract class ScanCapability extends PluginCapability {
  const ScanCapability();

  /// 整页推入扫一扫。
  ///
  /// [mode] 为 [ScanMode.addExtension] 时，扫到普通网址或拓展安装码会让用户
  /// 确认后关闭扫码页并返回 [ScanOutcome]；其它码走普通结果面板，返回 null。
  /// [ScanMode.generic] 下返回值恒为 null（沿用原来的页内处理）。
  Future<ScanOutcome?> open(BuildContext context, {ScanMode mode = ScanMode.generic});
}
