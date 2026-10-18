import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:campus_core/campus_core.dart';

import 'webview_policy.dart';

/// 内核自带的整页浏览器：加载 [url] 或 [html]，带加载进度与出错提示。
/// 供 [WebViewCapabilityImpl.openPage] 推入导航栈。
///
/// 带 [bridge] 时给页面注入一条网页 ↔ App 的通道：内核只管收发（垫片 `antiSIT`
/// + 原始通道 `antiSITBridge` + Promise 回填），支持哪些方法由 [bridge] 决定。
///
/// **导航**：内联 html（压缩包拓展）是一份自包含页面，主框架只许走本地方案，
/// 点到 http(s) 外链会拦下来交给系统浏览器（见 [decideMainFrameNavigation]）；
/// 网址形态就是普通浏览，不拦。
class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key, this.url, this.html, this.title = '', this.bridge});

  /// 二选一：[url] 优先；都为空就是空白页。
  final String? url;
  final String? html;
  final String title;

  /// 非空时注入 JS 通道（见 [WebBridge]）。
  final WebBridge? bridge;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

/// 网页里的接口垫片：把 `antiSIT.call/post` 变成一次消息 + 等 Promise 回填。
///
/// * 原始通道叫 `antiSITBridge`（内核 `addJavaScriptChannel` 给的名字，**不能**与
///   垫片自己定义的 `antiSIT` 重名），网页只该用 `antiSIT`；
/// * 每次导航加载完成后都要重注入（换页后旧上下文连同垫片一起没了）；
/// * 与 App 的调用约定：`{id, method, args}` → App 回 `__antiSITResolve(id, 值)`
///   或 `__antiSITReject(id, 错误文案)`。
const String _kBridgeShim = r'''
(function () {
  if (window.antiSIT) return;
  var seq = 0, waits = {};
  window.__antiSITResolve = function (id, v) { var w = waits[id]; if (w) { delete waits[id]; w.ok(v); } };
  window.__antiSITReject = function (id, e) { var w = waits[id]; if (w) { delete waits[id]; w.fail(new Error(e)); } };
  window.antiSIT = {
    call: function (method, args) {
      return new Promise(function (ok, fail) {
        var id = ++seq;
        waits[id] = { ok: ok, fail: fail };
        window.antiSITBridge.postMessage(JSON.stringify({
          id: id, method: String(method), args: args === undefined ? null : args
        }));
      });
    },
    // 不需要返回值时用它（内部吞掉错误，别让没接的 Promise 冒到控制台）
    post: function (method, args) { this.call(method, args).catch(function () {}); }
  };
})();
''';

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  double _progress = 0; // 0 = 没在加载
  String? _error;

  /// 这份内容是「内联 html」（压缩包拓展）还是「网址」——导航判定按它分岔。
  bool get _inline =>
      widget.html != null && (widget.url == null || widget.url!.trim().isEmpty);

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => mounted ? setState(() => _progress = p / 100) : null,
        onPageFinished: (_) => _injectBridge(),
        onNavigationRequest: _onNavigationRequest,
        onWebResourceError: (e) {
          // 主文档失败才提示；子资源（图片等）失败不打扰
          if (e.isForMainFrame ?? false) {
            if (mounted) setState(() => _error = e.description);
          }
        },
      ));
    if (widget.bridge != null) {
      _controller.addJavaScriptChannel('antiSITBridge', onMessageReceived: _onBridgeCall);
    }
    _load();
  }

  /// 导航守卫：内联页里的外链不在这儿加载，交给系统浏览器。
  Future<NavigationDecision> _onNavigationRequest(NavigationRequest req) async {
    switch (decideMainFrameNavigation(
      req.url,
      isMainFrame: req.isMainFrame,
      fromInlineHtml: _inline,
    )) {
      case NavAction.allow:
        return NavigationDecision.navigate;
      case NavAction.openExternal:
        await _openExternally(req.url);
        return NavigationDecision.prevent;
      case NavAction.block:
        return NavigationDecision.prevent;
    }
  }

  /// 用系统浏览器打开（不是应用内）——内联页不做浏览器。
  Future<void> _openExternally(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) setState(() => _error = '打不开这个链接：$url');
  }

  Future<void> _load() async {
    final url = widget.url;
    if (url != null && url.trim().isNotEmpty) {
      final uri = Uri.tryParse(url.trim());
      if (uri == null || !uri.hasScheme) {
        if (mounted) setState(() => _error = '网址格式不对：$url');
        return;
      }
      await _controller.loadRequest(uri);
    } else if (widget.html != null) {
      // 内联页：垫片写进 html 本身，网页第一个同步脚本就能用 antiSIT
      final html = widget.bridge == null
          ? widget.html!
          : injectBridgeShim(widget.html!, _kBridgeShim);
      await _controller.loadHtmlString(html);
    }
  }

  /// 页面加载完成后注入垫片：网页里才有 `window.antiSIT` 可用。
  Future<void> _injectBridge() async {
    if (widget.bridge == null) return;
    try {
      await _controller.runJavaScript(_kBridgeShim);
    } catch (_) {
      // 注入失败（页面拒绝执行脚本之类）不该把整页搞崩：网页仍可正常使用
    }
  }

  /// 网页发来的一次调用：分发 → 把结果（或错误）回填给它那个 Promise。
  Future<void> _onBridgeCall(JavaScriptMessage message) async {
    final bridge = widget.bridge;
    if (bridge == null) return;
    Object? id;
    try {
      final req = jsonDecode(message.message);
      if (req is! Map) throw const FormatException('调用格式不对');
      id = req['id'];
      final result = await bridge.call('${req['method']}', req['args']);
      await _reply('__antiSITResolve', id, result);
    } catch (e) {
      // 分发出错（未知方法 / 参数不对）也要回给网页，否则它的 Promise 永远悬着
      await _reply('__antiSITReject', id, '$e');
    }
  }

  Future<void> _reply(String fn, Object? id, Object? payload) async {
    try {
      await _controller
          .runJavaScript('window.$fn(${jsonEncode(id)}, ${jsonEncode(payload)})');
    } catch (_) {
      // 页面已经走了：没人接就没人接
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.isEmpty ? '网页' : widget.title, overflow: TextOverflow.ellipsis),
        bottom: _progress > 0 && _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress, minHeight: 2),
              )
            : null,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Material(
              color: SemColors.dangerSoft,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(_error!,
                    style: TextStyle(fontSize: 12, color: SemColors.danger, height: 1.5)),
              ),
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
