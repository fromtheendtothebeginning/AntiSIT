import 'package:flutter/material.dart';

import 'capability.dart';

/// WebView 内核能力：将来「热插拔插件」（网页形态的插件）的运行基座。
///
/// 热插拔插件 = 以网页（HTML/JS）为前端的插件：内容不随 App 发版更新，
/// 宿主只提供内核与运行时约定。内核只负责三件事——
/// * 判断引擎在当前平台是否可用（[available]）；
/// * 给一个可嵌入的网页视图（[view]，将来的插件往自己的页面里放）；
/// * 整页打开一个网页（[openPage]，应用内浏览器）。
///
/// 插件清单 / JS 桥 / 生命周期这些上层协议属于将来的热插拔框架，内核不掺和；
/// 取用方式与其他能力一致：
/// `PluginRegistry.I.capability<WebViewCapability>(PluginIds.webview)`
/// ——插件停用（默认就是关的）或被剔除时取到 null。
abstract class WebViewCapability extends PluginCapability {
  const WebViewCapability();

  /// 引擎在当前平台是否可用（webview_flutter 只覆盖 Android / iOS）。
  bool get available;

  /// 可嵌入的网页视图。二选一给 [url] 或 [html]；都为空时渲染空白页。
  Widget view({String? url, String? html});

  /// 整页打开网页（应用内浏览器样式：标题 + 加载进度 + 出错提示）。
  /// [url] 与 [html] 都为空时直接打开空白页。
  Future<void> openPage(
    BuildContext context, {
    String? url,
    String? html,
    String title = '',
  });
}
