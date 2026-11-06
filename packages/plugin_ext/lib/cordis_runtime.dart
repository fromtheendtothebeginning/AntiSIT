import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:campus_core/campus_core.dart';

import 'extension_item.dart';

/// 一条 Cordis 拓展交给 WebView 的页面内容。
class CordisPage {
  const CordisPage({required this.html, required this.mainJs});

  final String html;
  final String mainJs;
}

/// Cordis 拓展运行时：把运行时 bundle、`antiSIT` 垫片、宿主服务和拓展自己的
/// `main.js` 拼成一份自包含页面。
///
/// 页面结构：
/// 1. `antiSIT` 垫片（网页第一个脚本就能用宿主通道）
/// 2. Cordis 运行时（MIT，assets/cordis.min.js）
/// 3. 引导脚本：建 Context、注册 `ui` / `storage` / `card` / `ai` / `app` /
///    `workshop` 服务，再把 `main.js` 当 ES module 加载并 `ctx.plugin(plugin)`
///
/// 拓展插件就是一个标准 Cordis 插件：
/// ```js
/// export default {
///   name: 'my-tool',
///   inject: ['ui'],
///   apply(ctx) { ctx.ui.root.textContent = 'hello' },
/// }
/// ```
class CordisRuntime {
  CordisRuntime._();

  static const String _assetKey = 'packages/plugin_ext/assets/cordis.min.js';

  static String? _runtime;

  /// 读一次 Cordis bundle（约 31 KB），之后走内存缓存。
  static Future<String> loadRuntime() async {
    final cached = _runtime;
    if (cached != null) return cached;
    final text = await rootBundle.loadString(_assetKey);
    _runtime = text;
    return text;
  }

  /// 生成页面。[allowNetwork] 为 false 时用 CSP 掐掉 fetch / 外链图片，
  /// 与市场拓展的 `network` 权限保持一致。
  static Future<CordisPage> buildPage({
    required ExtensionItem item,
    required String mainJs,
    String css = '',
    required bool allowNetwork,
    required String appVersion,
  }) async {
    final runtime = await loadRuntime();
    final html = _html(
      item: item,
      runtime: runtime,
      bootstrap: _bootstrap(
        item: item,
        mainJs: mainJs,
        css: css,
        appVersion: appVersion,
      ),
      allowNetwork: allowNetwork,
    );
    return CordisPage(html: html, mainJs: mainJs);
  }

  static String _bootstrap({
    required ExtensionItem item,
    required String mainJs,
    required String css,
    required String appVersion,
  }) {
    // 代码走 base64：不跟 <script> / JSON 转义打架，也不把源码直接摊在 HTML 里。
    final code = base64Encode(utf8.encode(mainJs));
    final style = base64Encode(utf8.encode(css));
    final meta = jsonEncode({
      'id': item.id,
      'name': item.name,
      'permissions': item.permissions,
      'appVersion': appVersion,
    });
    return '''
(function () {
  var META = $meta;
  var MAIN_B64 = "$code";
  var CSS_B64 = "$style";
  var root = document.getElementById('root');
  var boot = document.getElementById('boot');
  function decodeB64(s) {
    var bin = atob(s), bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new TextDecoder('utf-8').decode(bytes);
  }
  function fail(e) {
    var text = e && (e.stack || e.message) || String(e);
    window.__antisitError = text;
    if (boot) boot.remove();
    var box = document.createElement('pre');
    box.className = 'antisit-error';
    box.textContent = '拓展启动失败\\n\\n' + text;
    (root || document.body).appendChild(box);
    console.error('[Cordis]', e);
  }
  function call(method, args) { return window.antiSIT.call(method, args); }
  (async function () {
    try {
      if (!window.Cordis) throw new Error('Cordis 运行时没有加载');
      var Context = window.Cordis.Context;
      var Service = window.Cordis.Service;
      var ctx = new Context();
      window.__antisitCtx = ctx;

      var theme = {};
      try { theme = await call('theme'); } catch (_) {}

      class Ui extends Service {
        constructor(c) {
          super(c, 'ui');
          this.root = root || document.body;
          this.theme = theme;
        }
        toast(text) { return call('toast', { text: String(text) }); }
        close() { return call('close'); }
      }
      class Storage extends Service {
        constructor(c) { super(c, 'storage'); }
        get(key) { return call('storage.get', { key: String(key) }); }
        set(key, value) { return call('storage.set', { key: String(key), value: value }); }
        remove(key) { return call('storage.remove', { key: String(key) }); }
      }
      class Card extends Service {
        constructor(c) { super(c, 'card'); }
        setName(text) { return call('card.setName', { text: String(text) }); }
        setDesc(text) { return call('card.setDesc', { text: String(text) }); }
        setIcon(text) { return call('card.setIcon', { text: String(text) }); }
      }
      class Ai extends Service {
        constructor(c) { super(c, 'ai'); }
        chat(prompt, options) {
          options = options || {};
          return call('ai.chat', {
            prompt: String(prompt),
            system: options.system,
            maxTokens: options.maxTokens
          });
        }
        chatTools(payload) { return call('ai.chatTools', payload); }
      }
      class App extends Service {
        constructor(c) {
          super(c, 'app');
          this.version = META.appVersion;
          this.id = META.id;
          this.name = META.name;
          this.permissions = META.permissions || [];
        }
        close() { return call('close'); }
      }
      class Workshop extends Service {
        constructor(c) { super(c, 'workshop'); }
        list() { return call('workshop.list'); }
        create(name) { return call('workshop.create', { name: name }); }
        files(draftId) { return call('workshop.files', { draftId: draftId }); }
        read(draftId, path) { return call('workshop.read', { draftId: draftId, path: path }); }
        write(draftId, path, content, expectedVersion) {
          return call('workshop.write', {
            draftId: draftId, path: path, content: content,
            expectedVersion: expectedVersion
          });
        }
        remove(draftId, path, expectedVersion) {
          return call('workshop.delete', {
            draftId: draftId, path: path, expectedVersion: expectedVersion
          });
        }
        validate(draftId) { return call('workshop.validate', { draftId: draftId }); }
        install(draftId) { return call('workshop.install', { draftId: draftId }); }
        preview(draftId) { return call('workshop.preview', { draftId: draftId }); }
        loadSession(draftId) { return call('workshop.session.get', { draftId: draftId }); }
        saveSession(draftId, data) {
          return call('workshop.session.set', { draftId: draftId, data: data });
        }
      }
      await ctx.plugin(Ui);
      await ctx.plugin(Storage);
      await ctx.plugin(Card);
      await ctx.plugin(Ai);
      await ctx.plugin(App);
      await ctx.plugin(Workshop);

      var css = decodeB64(CSS_B64);
      if (css) {
        var style = document.createElement('style');
        style.textContent = css;
        document.head.appendChild(style);
      }
      if (theme.bg) document.documentElement.style.setProperty('--antisit-bg', theme.bg);
      if (theme.card) document.documentElement.style.setProperty('--antisit-card', theme.card);
      if (theme.textPrimary) document.documentElement.style.setProperty('--antisit-fg', theme.textPrimary);
      if (theme.accent) document.documentElement.style.setProperty('--antisit-accent', theme.accent);
      if (theme.border) document.documentElement.style.setProperty('--antisit-border', theme.border);
      document.body.style.background = theme.bg || '';
      document.body.style.color = theme.textPrimary || '';

      var blob = new Blob([decodeB64(MAIN_B64)], { type: 'text/javascript' });
      var url = URL.createObjectURL(blob);
      try {
        var mod = await import(url);
        var plugin = mod.default || mod.plugin || mod;
        if (typeof plugin !== 'function' && !(plugin && typeof plugin.apply === 'function')) {
          throw new Error('main.js 需要 export default 一个 Cordis 插件（函数或带 apply 的对象）');
        }
        await ctx.plugin(plugin);
      } finally {
        URL.revokeObjectURL(url);
      }
      if (boot) boot.remove();
      window.__antisitReady = true;
      window.dispatchEvent(new CustomEvent('antisit-ready'));
    } catch (e) {
      fail(e);
    }
  })();

  window.addEventListener('pagehide', function () {
    try { window.__antisitCtx && window.__antisitCtx.fiber && window.__antisitCtx.fiber.dispose(); } catch (_) {}
  });
})();
''';
  }

  static String _html({
    required ExtensionItem item,
    required String runtime,
    required String bootstrap,
    required bool allowNetwork,
  }) {
    final csp = allowNetwork
        ? "default-src 'none'; script-src 'unsafe-inline' blob:; style-src 'unsafe-inline'; "
            "img-src data: https:; font-src data: https:; media-src https:; "
            "connect-src https:; form-action 'none'; base-uri 'none'"
        : "default-src 'none'; script-src 'unsafe-inline' blob:; style-src 'unsafe-inline'; "
            "img-src data:; font-src data:; connect-src 'none'; "
            "form-action 'none'; base-uri 'none'";
    String safeScript(String s) => s.replaceAll('</script', r'<\/script');
    return '''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta http-equiv="Content-Security-Policy" content="$csp">
<style>
html,body{margin:0;padding:0;min-height:100%;}
body{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;}
#root{min-height:100vh;box-sizing:border-box;}
#boot{padding:24px;color:#888;font-size:13px;}
.antisit-error{white-space:pre-wrap;word-break:break-word;margin:0;padding:16px;
  background:#2b1111;color:#ffb4b4;font:12px/1.6 ui-monospace,Consolas,monospace;}
</style>
</head>
<body>
<div id="root"></div>
<div id="boot">正在启动「${_escapeHtml(item.name)}」…</div>
<script>${safeScript(kWebViewBridgeShim)}</script>
<script>${safeScript(runtime)}</script>
<script>${safeScript(bootstrap)}</script>
</body>
</html>''';
  }

  static String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
