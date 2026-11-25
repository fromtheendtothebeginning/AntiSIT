import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'webview_host.dart';
import 'webview_page.dart';

/// WebView 内核能力实现（webview_flutter）。
/// 只覆盖 Android / iOS：桌面端 [available] 为假，调用方按「不可用」降级。
class WebViewCapabilityImpl extends WebViewCapability {
  const WebViewCapabilityImpl();

  static bool get _platformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  bool get available => _platformSupported;

  @override
  Widget view({String? url, String? html}) =>
      WebViewPage(url: url, html: html);

  /// 可编程网页视图（[WebViewHost]）：要注入脚本、收网页消息的页面用；平台不支持时返回 null。
  @override
  WebViewHost? host({
    required String url,
    required String channel,
    required void Function(WebViewHost host, String message) onMessage,
    required void Function(WebViewHost host) onPageReady,
    Map<String, String> cookies = const {},
    String proxy = '',
  }) {
    if (!_platformSupported) return null;
    return KernelWebViewHost(
      url: url,
      channel: channel,
      cookies: cookies,
      proxy: proxy,
      onMessage: onMessage,
      onPageReady: onPageReady,
    );
  }

  @override
  Future<void> openPage(
    BuildContext context, {
    String? url,
    String? html,
    String title = '',
    WebBridge? bridge,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => WebViewPage(url: url, html: html, title: title, bridge: bridge),
      ),
    );
  }
}
