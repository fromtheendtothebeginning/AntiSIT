import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'capability.dart';

/// WebView 内核能力：热插拔插件（网页形态的插件）的运行基座。
///
/// 内核只做三件事：判断引擎在当前平台是否可用、给一个可嵌入的网页视图、整页打开网页
/// 并可带一条网页 ↔ App 的调用通道；插件清单 / 生命周期等上层协议不在这里。
abstract class WebViewCapability extends PluginCapability {
  const WebViewCapability();

  /// 引擎在当前平台是否可用（webview_flutter 只覆盖 Android / iOS）。
  bool get available;

  /// 可嵌入的网页视图。二选一给 [url] 或 [html]；都为空时渲染空白页。
  Widget view({String? url, String? html});

  /// 整页打开网页（应用内浏览器样式：标题 + 加载进度 + 出错提示）。
  ///
  /// [bridge] 非空时注入 JS 通道；[html] 形态下点到 http(s) 外链会交给系统浏览器，
  /// 免得通道跟着跳到别人的页面上，[url] 形态则是普通浏览、不拦。
  Future<void> openPage(
    BuildContext context, {
    String? url,
    String? html,
    String title = '',
    WebBridge? bridge,
  });

  /// 建一个**可编程**的网页视图（见 [WebViewHost]），默认实现返回 null。
  ///
  /// [channel] 是网页侧 `window[channel].postMessage(...)` 的通道名；
  /// [onPageReady] 在每次主文档加载完成后回调（注入脚本放这里最稳）；
  /// [cookies] 先写进 WebView 的 Cookie（name → value，按 [url] 的域名）；
  /// [proxy] 这页要走的 HTTP 代理（`http://host:port`），空 = 直连。
  WebViewHost? host({
    required String url,
    required String channel,
    required void Function(WebViewHost host, String message) onMessage,
    required void Function(WebViewHost host) onPageReady,
    Map<String, String> cookies = const {},
    String proxy = '',
  }) =>
      null;
}

/// 一个**可编程**的网页视图：界面长什么样、放在页面哪一块全由调用方决定。
///
/// 调用方在 `initState` 里建，`dispose` 里 [dispose]；[view] 只放进树一次。
abstract class WebViewHost {
  /// 网页视图（一个 host 只应放进页面一次）。
  Widget get view;

  /// 当前地址（主框架导航会更新）。
  String get url;

  /// 加载进度 0..1：0 = 没在加载。
  ValueListenable<double> get progress;

  /// 主文档加载失败的文案；成功加载后清空。
  ValueListenable<String?> get error;

  /// 注入脚本执行（不等返回值；注入失败不抛，避免把页面搞崩）。
  Future<void> run(String js);

  /// 导航到新地址。
  Future<void> load(String url);

  /// 重新加载当前地址。
  Future<void> reload();

  void dispose();
}

/// 网页里的接口垫片：把 `antiSIT.call/post` 变成一次消息 + 等 Promise 回填，
/// 并提供 `antiSIT.on(event, fn)` 接收 App 推下来的流式事件。
///
/// 原始通道叫 `antiSITBridge`（不能与垫片自己定义的 `antiSIT` 重名）；
/// 每次导航加载完成后都要重注入（换页后旧上下文连同垫片一起没了）。
const String kWebViewBridgeShim = r'''
(function () {
  if (window.antiSIT) return;
  var seq = 0, waits = {}, listeners = {};
  window.__antiSITResolve = function (id, v) { var w = waits[id]; if (w) { delete waits[id]; w.ok(v); } };
  window.__antiSITReject = function (id, e) { var w = waits[id]; if (w) { delete waits[id]; w.fail(new Error(e)); } };
  window.__antiSITEvent = function (name, data) {
    var list = listeners[name];
    if (!list) return;
    for (var i = 0; i < list.length; i++) {
      try { list[i](data); } catch (e) { console.error('[antiSIT]', name, e); }
    }
  };
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
    post: function (method, args) { this.call(method, args).catch(function () {}); },
    // 订阅 App 推下来的事件（流式输出、进度等）；返回取消订阅函数
    on: function (name, fn) {
      var key = String(name);
      (listeners[key] = listeners[key] || []).push(fn);
      return function () {
        var list = listeners[key];
        if (!list) return;
        var i = list.indexOf(fn);
        if (i >= 0) list.splice(i, 1);
      };
    }
  };
})();
''';

/// 内核 → 网页的下行通道：给 [WebBridge.attachEventSink] 用（目前用于 AI 流式输出）。
abstract interface class WebBridgeEventSink {
  void emit(String event, Object? data);
}

/// 网页 ↔ App 的调用通道：内核只负责收发，**支持哪些方法完全由调用方决定**。
///
/// 网页侧统一走内核注入的垫片：`await antiSIT.call('theme')` 取返回值，
/// `antiSIT.post('toast', {...})` 不取；实现抛出的异常会以 Promise reject 回给网页。
abstract class WebBridge {
  const WebBridge();

  /// 内核在页面就绪后挂上下行通道；页面关掉时挂 null。
  /// 需要推流的实现覆写它并保存 [sink]，用 `sink.emit(事件名, 数据)` 发事件。
  void attachEventSink(WebBridgeEventSink? sink) {}

  /// 网页侧页面栈深度变化：`true` = 系统返回键应先交给网页的 `window.__antiSITBack()`。
  void attachBackGuard(void Function(bool canGoBack)? guard) {}

  /// 处理一次调用。[method] 由网页给出，[args] 是它带上的原样参数。
  Future<Object?> call(String method, Object? args);
}
