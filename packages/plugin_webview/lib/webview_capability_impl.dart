import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'webview_page.dart';

/// WebView 内核能力实现（webview_flutter）。
///
/// webview_flutter 只覆盖 Android / iOS：桌面端（Windows / macOS / Linux）
/// [available] 为假，调用方按「不可用」降级——能力查询在插件停用（默认态）时
/// 本来就返回 null，启用但平台不支持时用 [available] 区分。
class WebViewCapabilityImpl extends WebViewCapability {
  const WebViewCapabilityImpl();

  static bool get _platformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  bool get available => _platformSupported;

  @override
  Widget view({String? url, String? html}) =>
      WebViewPage(url: url, html: html);

  @override
  Future<void> openPage(
    BuildContext context, {
    String? url,
    String? html,
    String title = '',
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => WebViewPage(url: url, html: html, title: title),
      ),
    );
  }
}
