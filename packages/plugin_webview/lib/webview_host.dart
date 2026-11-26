import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:campus_core/campus_core.dart';

/// 内核实现的可编程网页视图（[WebViewHost]）：把控制器交给调用方。
/// 与整页浏览器 [WebViewPage] 分工：那个是「看网页」，这个供注入脚本、改写页面、收网页消息的场景，
/// 界面与交互不掺和（页面自己排 AppBar / 面板）。
class KernelWebViewHost implements WebViewHost {
  KernelWebViewHost({
    required String url,
    required String channel,
    Map<String, String> cookies = const {},
    String proxy = '',
    required void Function(WebViewHost host, String message) onMessage,
    required void Function(WebViewHost host) onPageReady,
  })  : _url = url,
        _cookies = cookies,
        _proxy = proxy {
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
        // 每次主文档加载完成都回调：换页后调用方要重新注入脚本。
        onPageFinished: (_) {
          if (_disposed) return;
          _progress.value = 0;
          _error.value = null;
          onPageReady(this);
        },
        onWebResourceError: (e) {
          // 子资源（图片 / 字体）失败不打扰，只有主文档失败才算这页挂了。
          if (_disposed || !(e.isForMainFrame ?? false)) return;
          _progress.value = 0;
          _error.value = e.description;
        },
      ));
    if (url.trim().isNotEmpty) unawaited(_boot(url));
  }

  late final WebViewController _ctrl;
  final Map<String, String> _cookies;

  /// HTTP 代理（`http://host:port`）：服务器模式的评教页经校园隧道打开时用。
  /// 空 = 不改 WebView 的代理（直连模式）。
  final String _proxy;

  /// 代理是进程级的（Android WebView ProxyController），原生侧用这条通道设置 / 清除。
  static const MethodChannel _proxyChannel = MethodChannel('antisit/webview');
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
      // 页面已走 / 拒绝执行脚本：注入失败不该把整页搞崩，调用方自己会重扫。
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

  /// 首次加载：先设代理，再写 Cookie，最后发第一个请求——顺序反了网页拿到的是未登录页。
  Future<void> _boot(String url) async {
    await _applyProxy();
    await _applyCookies(url);
    await _loadQuiet(url);
  }

  Future<void> _applyProxy() async {
    if (_proxy.isEmpty) return;
    try {
      final ok = await _proxyChannel.invokeMethod<bool>('setProxy', {'url': _proxy});
      if (ok != true) debugPrint('[WebViewHost] 当前内核不支持网页代理，按直连处理');
    } catch (e) {
      // iOS / 桌面端没有这条通道：保持直连，页面自己会给出加载失败。
      debugPrint('[WebViewHost] 设置代理失败：$e');
    }
  }

  /// 把 [WebViewHost] 的 cookies 按目标域名写进 WebView（name → value）；失败不影响页面。
  Future<void> _applyCookies(String url) async {
    if (_cookies.isEmpty) return;
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return;
    final manager = WebViewCookieManager();
    for (final entry in _cookies.entries) {
      try {
        await manager.setCookie(WebViewCookie(
          name: entry.key,
          value: entry.value,
          domain: uri.host,
          path: '/',
        ));
      } catch (e) {
        debugPrint('[WebViewHost] 写 Cookie 失败 ${entry.key}：$e');
      }
    }
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
    // 代理是进程级的：不恢复的话，离开本页后其它 WebView 也会继续走校园隧道。
    if (_proxy.isNotEmpty) {
      unawaited(() async {
        try {
          await _proxyChannel.invokeMethod('setProxy', {'url': null});
        } catch (_) {}
      }());
    }
  }
}
