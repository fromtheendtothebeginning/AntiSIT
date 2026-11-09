import 'package:flutter/material.dart';

import 'capability.dart';

/// WebView 内核能力：将来「热插拔插件」（网页形态的插件）的运行基座。
///
/// 热插拔插件 = 以网页（HTML/JS）为前端的插件：内容不随 App 发版更新，
/// 宿主只提供内核与运行时约定。内核负责三件事——
/// * 判断引擎在当前平台是否可用（[available]）；
/// * 给一个可嵌入的网页视图（[view]，将来的插件往自己的页面里放）；
/// * 整页打开一个网页（[openPage]，应用内浏览器），可带一条网页 ↔ App 的调用通道（[WebBridge]）。
///
/// 插件清单 / 生命周期这些上层协议属于上层框架（内置前端见 `plugin_ext`），内核不掺和；
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
  /// [bridge] 非空时给这页注入 JS 通道：网页里能用内核垫片提供的 `antiSIT` 与 App 通话
  /// （给 [html] 时垫片直接写进 html，网页第一个同步脚本就能用；给 [url] 时在加载完成后注入）。
  ///
  /// **导航**：[html]（压缩包拓展那种自包含页面）里点到 http(s) 外链不会在应用内加载——
  /// 拦下来交给系统浏览器，免得通道跟着跳到别人的页面上；[url] 形态就是普通浏览，不拦。
  Future<void> openPage(
    BuildContext context, {
    String? url,
    String? html,
    String title = '',
    WebBridge? bridge,
  });
}

/// 网页里的接口垫片：把 `antiSIT.call/post` 变成一次消息 + 等 Promise 回填，
/// 并提供 `antiSIT.on(event, fn)` 接收 App 推下来的流式事件。
///
/// * 原始通道叫 `antiSITBridge`（内核 `addJavaScriptChannel` 给的名字，**不能**与
///   垫片自己定义的 `antiSIT` 重名），网页只该用 `antiSIT`；
/// * 每次导航加载完成后都要重注入（换页后旧上下文连同垫片一起没了）；
/// * 与 App 的调用约定：`{id, method, args}` → App 回 `__antiSITResolve(id, 值)`
///   或 `__antiSITReject(id, 错误文案)`；
/// * 下行事件：App 调 `window.__antiSITEvent(事件名, 数据)`，垫片分发给 `antiSIT.on` 订阅者。
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

/// 内核 → 网页的下行通道：给 [WebBridge.attachEventSink] 用。
/// 目前用于 AI 流式输出（App 把增量推给网页的 `antiSIT.on` 订阅者）。
abstract interface class WebBridgeEventSink {
  void emit(String event, Object? data);
}

/// 网页 ↔ App 的调用通道：内核只负责把网页的调用送进来、把返回值送回网页，
/// **支持哪些方法完全由调用方决定**（内置实现见 `plugin_ext`，方法表见
/// `docs/extensions.md`）。网页侧统一走内核注入的垫片，一个入口：
///
/// ```js
/// const theme = await antiSIT.call('theme');   // 需要返回值
/// antiSIT.post('toast', {text: '已保存'});      // 不需要返回值
/// ```
///
/// 实现方按 [method] 分发并返回 JSON 可编码的结果即可；抛出的异常会以错误回给网页
/// （Promise reject），网页侧自己决定怎么提示。
abstract class WebBridge {
  const WebBridge();

  /// 内核在页面就绪后挂上下行通道；页面关掉时挂 null。
  /// 需要推流的实现覆写它并保存 [sink]，用 `sink.emit(事件名, 数据)` 发事件。
  void attachEventSink(WebBridgeEventSink? sink) {}

  /// 处理一次调用。[method] 由网页给出，[args] 是它带上的原样参数
  /// （Map / List / 标量 / null，取决于网页怎么传）。
  Future<Object?> call(String method, Object? args);
}
