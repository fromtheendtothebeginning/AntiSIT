import 'package:flutter/widgets.dart';

import 'capability.dart';

/// 扫一扫的用途。
enum ScanMode {
  /// 普通扫码：二课签到 / 活动详情 / 网址，直接在扫码页里处理。
  generic,

  /// 给「拓展」页加东西：把结果交回调用方（扫码插件不碰拓展逻辑）。
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

/// 第三方插件源安装码：
/// `{"antisit":"source","repo":"owner/repo","fingerprint":"XXXX-XXXX-XXXX"}`。
class ScanSourceOutcome extends ScanOutcome {
  const ScanSourceOutcome({
    required this.repo,
    this.fingerprint,
    this.branch,
    this.name,
    required String raw,
  }) : super(raw);

  /// `owner/repo`，或一个完整的 https 目录地址。
  final String repo;

  /// 可选的公钥指纹（`XXXX-XXXX-XXXX`）；作者给了就必须一致。
  final String? fingerprint;
  final String? branch;
  final String? name;
}

/// 扫一扫能力：整页打开扫码功能（相机取景 + 相册识码 + 码型分流），实现方 `plugin_scan`。
abstract class ScanCapability extends PluginCapability {
  const ScanCapability();

  /// 整页推入扫一扫。
  ///
  /// [mode] 为 [ScanMode.addExtension] 时，扫到网址或拓展安装码会确认后关页并返回
  /// [ScanOutcome]，其它码走普通结果面板并返回 null；[ScanMode.generic] 下恒返回 null。
  Future<ScanOutcome?> open(BuildContext context, {ScanMode mode = ScanMode.generic});
}
