import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:campus_core/campus_core.dart';

/// 内核实现的可编程网页视图（[WebViewHost]）。
///
/// 与内核自带的整页浏览器 [WebViewPage] 的分工：那个是「看网页」，这个把控制器交给
/// 调用方——评教助手要在页面加载完成后注入扫描脚本、按项改写页面上的分值控件，
/// 并接收网页发回的消息。内核只负责建 WebView、注册通道、把加载事件转出去，
/// **界面与交互不掺和**（页面自己排 AppBar / 面板）。
class KernelWebViewHost implements WebViewHost {
  KernelWebViewHost({
    required String url,
    required String channel,
    required void Function(WebViewHost host, String message) onMessage,
    required void Function(WebViewHost host) onPageReady,
  }) : _url = url {
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(channel, onMessageReceived: (m) => onMessage(this, m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (_disposed) return;
          _progress.value = p / 100;
        },
        onUrlChange: (change) {
          final u = change.url;
          if (u == null || u.isEmpty || u == 'about:blank') return;
          _url = u;
          _error.value = null;
        },
        // 每次主文档加载完成都回调：换页后调用方要重新注入脚本
        onPageFinished: (_) {
          if (_disposed) return;
          _progress.value = 0;
          _error.value = null;
          onPageReady(this);
        },
        onWebResourceError: (e) {
          // 子资源（图片 / 字体）失败不打扰，只有主文档失败才算这页挂了
          if (_disposed || !(e.isForMainFrame ?? false)) return;
          _progress.value = 0;
          _error.value = e.description;
        },
      ));
    if (url.trim().isNotEmpty) unawaited(_loadQuiet(url));
  }

  late final WebViewController _ctrl;
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);
  String _url;
  bool _disposed = false;

  @override
  Widget get view => WebViewWidget(controller: _ctrl);

  @override
  String get url => _url;

  @override
  ValueListenable<double> get progress => _progress;

  @override
  ValueListenable<String?> get error => _error;

  @override
  Future<void> run(String js) async {
    if (_disposed) return;
    try {
      await _ctrl.runJavaScript(js);
    } catch (e) {
      // 页面已走 / 拒绝执行脚本：注入失败不该把整页搞崩，调用方自己会重扫
      debugPrint('[WebViewHost] 注入失败：$e');
    }
  }

  @override
  Future<void> load(String url) async {
    if (_disposed) return;
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      _error.value = '网址格式不对：$url';
      return;
    }
    _url = url;
    _error.value = null;
    await _loadQuiet(url);
  }

  Future<void> _loadQuiet(String url) async {
    try {
      await _ctrl.loadRequest(Uri.parse(url.trim()));
    } catch (e) {
      if (!_disposed) _error.value = '$e';
    }
  }

  @override
  Future<void> reload() async {
    if (_disposed) return;
    try {
      await _ctrl.reload();
    } catch (e) {
      if (!_disposed) _error.value = '$e';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _progress.dispose();
    _error.dispose();
  }
}
