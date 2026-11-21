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
/// 2. AntiUI 组件（CSS + `window.AntiUI`，风格与 App 一致）
/// 3. Cordis 运行时（MIT，assets/cordis.min.js）
/// 4. 引导脚本：建 Context、注册 `ui` / `storage` / `card` / `ai` / `notify` /
///    `secrets` / `net` / `clipboard` / `files` / `login` / `background` /
///    `permissions` / `app` / `workshop` 服务，再把 `main.js` 当 ES module 加载并 `ctx.plugin(plugin)`
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
  static const String _uiCssKey = 'packages/plugin_ext/assets/anti_ui.css';
  static const String _uiJsKey = 'packages/plugin_ext/assets/anti_ui.js';

  static String? _runtime;
  static String? _uiCss;
  static String? _uiJs;

  /// 读一次 Cordis bundle（约 31 KB），之后走内存缓存。
  static Future<String> loadRuntime() async {
    final cached = _runtime;
    if (cached != null) return cached;
    final text = await rootBundle.loadString(_assetKey);
    _runtime = text;
    return text;
  }

  /// AntiUI 组件（CSS + JS）：每个拓展页都注入，作者不用自己带一套样式。
  static Future<({String css, String js})> loadUiKit() async {
    final css = _uiCss ??= await rootBundle.loadString(_uiCssKey);
    final js = _uiJs ??= await rootBundle.loadString(_uiJsKey);
    return (css: css, js: js);
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
    final ui = await loadUiKit();
    final html = _html(
      item: item,
      runtime: runtime,
      uiCss: ui.css,
      uiJs: ui.js,
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
      'fromMarket': item.fromMarket,
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

  // blob: URL 在页面内没有可读回的句柄，而市场拓展默认把网络连接全禁掉：
  // 在拓展代码之前接管 createObjectURL，记下 URL → Blob，下载钩子直接取。
  var BLOBS = {};
  try {
    var createObjectURL = URL.createObjectURL;
    URL.createObjectURL = function (obj) {
      var url = createObjectURL.call(URL, obj);
      try { BLOBS[url] = obj; } catch (_) {}
      return url;
    };
    var revokeObjectURL = URL.revokeObjectURL;
    URL.revokeObjectURL = function (url) {
      try { delete BLOBS[url]; } catch (_) {}
      return revokeObjectURL.call(URL, url);
    };
  } catch (_) {}

  function dataUrlBlob(url) {
    var comma = url.indexOf(',');
    if (comma < 0) return null;
    var meta = url.slice(5, comma);
    var body = url.slice(comma + 1);
    var mime = meta.split(';')[0] || 'application/octet-stream';
    try {
      if (/;base64/i.test(meta)) {
        var bin = atob(body);
        var bytes = new Uint8Array(bin.length);
        for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
        return new Blob([bytes], { type: mime });
      }
      return new Blob([decodeURIComponent(body)], { type: mime });
    } catch (_) {
      return null;
    }
  }

  // 页面内生成的下载（blob: / data:）在 WebView 里没有原生下载入口：
  // 拦下带 download 的链接，转成 ctx.files.save 交给系统「保存到」。
  // http(s) 下载由内核的 DownloadManager 监听处理，这里不碰。
  function installDownloadHook() {
    var canSave = !META.fromMarket ||
      (META.permissions || []).indexOf('files') >= 0;
    if (!canSave || !window.AntiUI) return;
    var EXT = {
      'text/plain': '.txt', 'text/csv': '.csv', 'application/json': '.json',
      'application/pdf': '.pdf', 'application/zip': '.zip',
      'image/png': '.png', 'image/jpeg': '.jpg', 'image/gif': '.gif',
      'image/webp': '.webp', 'image/svg+xml': '.svg',
      'text/html': '.html', 'text/markdown': '.md',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': '.xlsx',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document': '.docx'
    };
    document.addEventListener('click', function (e) {
      var node = e.target;
      if (node && node.nodeType !== 1) node = node.parentElement;
      var link = node && node.closest ? node.closest('a[download]') : null;
      if (!link) return;
      var href = link.getAttribute('href') || link.href || '';
      var isBlob = href.indexOf('blob:') === 0;
      if (!isBlob && href.indexOf('data:') !== 0) return;
      e.preventDefault();
      var name = link.getAttribute('download') || '下载';
      var blob = isBlob ? BLOBS[href] : dataUrlBlob(href);
      if (!blob) {
        window.AntiUI.toast('无法读取下载内容');
        return;
      }
      if (blob.size > 8 * 1024 * 1024) {
        window.AntiUI.toast('文件太大（最多 8 MB），请改用其他方式导出');
        return;
      }
      new Promise(function (ok, fail) {
        var reader = new FileReader();
        reader.onload = function () {
          var result = String(reader.result || '');
          ok({ b64: result.split(',')[1] || '', mime: blob.type || '' });
        };
        reader.onerror = fail;
        reader.readAsDataURL(blob);
      }).then(function (data) {
        var fileName = name;
        if (fileName.indexOf('.') < 0 && EXT[data.mime]) fileName += EXT[data.mime];
        return call('files.save', { name: fileName, base64: data.b64, mime: data.mime })
          .then(function (saved) {
            if (saved) window.AntiUI.toast('已保存 ' + fileName);
          });
      }).catch(function (err) {
        console.warn('[Cordis] 下载失败', err);
        window.AntiUI.toast('保存失败：' + (err && (err.message || err)));
      });
    }, true);
  }

  // 页面栈：拓展用 ctx.ui.push() 叠自己的子页面。栈非空时系统返回键先由
  // __antiSITBack 回退一层（宿主靠 ui.backDepth 知道该不该拦），栈空了才关整页。
  var pageStack = [];
  function stackTop() { return pageStack.length ? pageStack[pageStack.length - 1] : null; }
  function stackSync() {
    try { call('ui.backDepth', { depth: pageStack.length }); } catch (_) {}
  }
  window.__antiSITBack = function () {
    var top = stackTop();
    if (!top) return false;
    pageStack.pop();
    try { top.el.remove(); } catch (_) {}
    try { top.onPop && top.onPop(); } catch (e) { console.error('[Cordis] onPop', e); }
    stackSync();
    return true;
  };

  (async function () {
    try {
      if (!window.Cordis) throw new Error('Cordis 运行时没有加载');
      var Context = window.Cordis.Context;
      var Service = window.Cordis.Service;
      var ctx = new Context();
      window.__antisitCtx = ctx;

      var theme = {};
      var themeChanged = false;
      // 主题 / 夜间模式切换：原生侧推完整色板，CSS 变量和 ctx.ui.theme 一起刷新。
      try {
        window.antiSIT.on('theme.change', function (next) {
          themeChanged = true;
          theme = next;
          applyTheme(next);
          try { ctx.ui.theme = next; } catch (_) {}
        });
      } catch (_) {}
      try { theme = await call('theme'); } catch (_) {}
      // 取主题期间已经收到更新的推送：以推送为准，别用旧快照覆盖
      if (!themeChanged) applyTheme(theme);

      class Ui extends Service {
        constructor(c) {
          super(c, 'ui');
          this.root = root || document.body;
          this.theme = window.__antisitTheme || theme;
          // 统一组件（anti_ui.js 注入）：按钮 / 卡片 / 弹层 / 空态都在这里
          this.kit = window.AntiUI || null;
        }
        toast(text) { return call('toast', { text: String(text) }); }
        close() { return call('close'); }
        confirm(options) { return window.AntiUI ? window.AntiUI.confirm(options) : Promise.resolve(false); }
        sheet(options) { return window.AntiUI ? window.AntiUI.sheet(options) : null; }
        // 订阅主题变化；返回取消订阅函数。AntiUI 自己会跟 CSS 变量走，不用手动重画。
        onThemeChange(fn) { return window.antiSIT.on('theme.change', fn); }

        /// 叠一层子页面：返回 { root, close }，往 root 里画自己的内容。
        /// [options.onPop] 在退回上一层后回调；系统返回键 / 左上角箭头会先退它。
        push(options) {
          options = options || {};
          var el = document.createElement('div');
          el.className = 'antisit-stack-page';
          el.style.position = 'fixed';
          el.style.inset = '0';
          el.style.overflow = 'auto';
          el.style.boxSizing = 'border-box';
          el.style.background = 'var(--antisit-bg, #fff)';
          el.style.backgroundImage = 'var(--antisit-wells, none)';
          el.style.backgroundAttachment = 'fixed';
          el.style.zIndex = String(100 + pageStack.length);
          (this.root || document.body).appendChild(el);
          var entry = {
            el: el,
            onPop: typeof options.onPop === 'function' ? options.onPop : null,
          };
          pageStack.push(entry);
          stackSync();
          return {
            root: el,
            close: function () {
              if (stackTop() !== entry) return false;
              return window.__antiSITBack();
            },
          };
        }

        /// 退回上一层；已经在最外层返回 false。
        pop() { return window.__antiSITBack(); }

        get depth() { return pageStack.length; }
        get canGoBack() { return pageStack.length > 0; }
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
        chatToolsStream(payload) { return call('ai.chatToolsStream', payload); }
      }
      class Notify extends Service {
        constructor(c) { super(c, 'notify'); }
        show(payload) { return call('notify.show', payload || {}); }
        popup(payload) {
          var p = payload || {};
          return call('notify.show', {
            title: p.title, body: p.body, key: p.key, popup: true
          });
        }
        schedule(payload) { return call('notify.schedule', payload || {}); }
        cancel(key) { return call('notify.cancel', { key: String(key) }); }
        cancelAll() { return call('notify.cancelAll'); }
      }
      class Secrets extends Service {
        constructor(c) { super(c, 'secrets'); }
        get(key) { return call('secrets.get', { key: String(key) }); }
        set(key, value) {
          return call('secrets.set', { key: String(key), value: String(value) });
        }
        remove(key) { return call('secrets.remove', { key: String(key) }); }
      }
      class Net extends Service {
        constructor(c) { super(c, 'net'); }
        request(options) { return call('net.request', options || {}); }
        // 校内明文 http：market 包要在 ext.json 里声明 campus_net
        campus(options) { return call('net.campus', options || {}); }
      }
      class Clipboard extends Service {
        constructor(c) { super(c, 'clipboard'); }
        read() { return call('clipboard.read'); }
        write(text) { return call('clipboard.write', { text: String(text) }); }
      }
      class Files extends Service {
        constructor(c) { super(c, 'files'); }
        // {accept?, multiple?, encoding?} → {files: [{name, size, mime, text?/base64?}]}
        pick(options) { return call('files.pick', options || {}); }
        // {name, text?/base64?, mime?} → true / false（用户取消）
        save(options) { return call('files.save', options || {}); }
      }
      class Login extends Service {
        constructor(c) { super(c, 'login'); }
        open(options) { return call('login.open', options || {}); }
        // 退出登录：清掉这些域在系统 CookieStore 里的 Cookie
        clear(options) { return call('login.clear', options || {}); }
      }
      class Background extends Service {
        constructor(c) { super(c, 'background'); }
        keepAlive(options) { return call('background.keepAlive', options || {}); }
      }
      class Permissions extends Service {
        constructor(c) { super(c, 'permissions'); }
        request(options) { return call('permissions.request', options || {}); }
        status(options) { return call('permissions.status', options || {}); }
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
        deleteDraft(draftId) { return call('workshop.deleteDraft', { draftId: draftId }); }
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
        renameDraft(draftId, name) {
          return call('workshop.renameDraft', { draftId: draftId, name: name });
        }
        install(draftId) { return call('workshop.install', { draftId: draftId }); }
        preview(draftId) { return call('workshop.preview', { draftId: draftId }); }
        publish(draftId) { return call('workshop.publish', { draftId: draftId }); }
        listConversations(draftId) {
          return call('workshop.session.list', { draftId: draftId });
        }
        createConversation(draftId, title) {
          return call('workshop.session.create', { draftId: draftId, title: title });
        }
        renameConversation(draftId, conversationId, title) {
          return call('workshop.session.rename', {
            draftId: draftId, conversationId: conversationId, title: title
          });
        }
        deleteConversation(draftId, conversationId) {
          return call('workshop.session.delete', {
            draftId: draftId, conversationId: conversationId
          });
        }
        loadSession(draftId, conversationId) {
          return call('workshop.session.get', {
            draftId: draftId, conversationId: conversationId
          });
        }
        saveSession(draftId, conversationId, data) {
          return call('workshop.session.set', {
            draftId: draftId, conversationId: conversationId, data: data
          });
        }
        listSkills() { return call('workshop.skills.list'); }
        readSkill(id) { return call('workshop.skills.read', { id: id }); }
        installSkill(name, description, content) {
          return call('workshop.skills.install', {
            name: name, description: description, content: content
          });
        }
        deleteSkill(id, userInitiated) {
          return call('workshop.skills.delete', { id: id, userInitiated: !!userInitiated });
        }
        setFullAccess(enabled) {
          return call('workshop.setFullAccess', { enabled: enabled });
        }
      }
      await ctx.plugin(Ui);
      await ctx.plugin(Storage);
      await ctx.plugin(Card);
      await ctx.plugin(Ai);
      await ctx.plugin(Notify);
      await ctx.plugin(Secrets);
      await ctx.plugin(Net);
      await ctx.plugin(Clipboard);
      await ctx.plugin(Files);
      await ctx.plugin(Login);
      await ctx.plugin(Background);
      await ctx.plugin(Permissions);
      await ctx.plugin(App);
      await ctx.plugin(Workshop);

      var css = decodeB64(CSS_B64);
      if (css) {
        var style = document.createElement('style');
        style.textContent = css;
        document.head.appendChild(style);
      }
      // 颜色合成：深色玻璃主题的 card 是半透明白（8%），弹层 / 卡片要铺
      // 「合成到背景之后」的实底，否则会白成一片（深色模式适配的关键）。
      function parseColor(v) {
        if (!v) return null;
        // 不用正则：Dart 字符串里的美元符号会当插值，反斜杠转义也容易踩坑
        if (v.indexOf('rgb(') === 0 || v.indexOf('rgba(') === 0) {
          var inner = v.slice(v.indexOf('(') + 1, v.indexOf(')'));
          var p = inner.split(',').map(function (x) { return parseFloat(x); });
          return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
        }
        if (v.charAt(0) === '#' && v.length >= 7) {
          var n = parseInt(v.slice(1, 7), 16);
          if (!isNaN(n)) {
            return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255, a: 1 };
          }
        }
        return null;
      }
      function over(fg, bg) {
        var f = parseColor(fg);
        if (!f) return fg;
        var b = parseColor(bg) || { r: 255, g: 255, b: 255, a: 1 };
        var a = f.a + b.a * (1 - f.a);
        if (a <= 0) return 'transparent';
        var r = Math.round((f.r * f.a + b.r * b.a * (1 - f.a)) / a);
        var g = Math.round((f.g * f.a + b.g * b.a * (1 - f.a)) / a);
        var bl = Math.round((f.b * f.a + b.b * b.a * (1 - f.a)) / a);
        return 'rgb(' + r + ',' + g + ',' + bl + ')';
      }
      // Flutter 的 GlassWell：center 是 -1..1 的对齐坐标，radius 是「短边」的倍数；
      // CSS 用 vmin 对应短边，stops 0 → 62% 与 GlassBackground 一致。
      function wellsCss(wells) {
        if (!wells || !wells.length) return '';
        var out = [];
        for (var i = 0; i < wells.length; i++) {
          var w = wells[i];
          var x = Math.round((Number(w.x) + 1) * 50);
          var y = Math.round((Number(w.y) + 1) * 50);
          var r = Math.round(Number(w.radius) * 100);
          out.push('radial-gradient(circle ' + r + 'vmin at ' + x + '% ' + y +
            '%, ' + w.color + ', transparent 62%)');
        }
        return out.join(', ');
      }
      function px(v) {
        return typeof v === 'number' ? v + 'px' : '';
      }
      // 完整色板 → CSS 变量；夜间模式同时切 .dark / color-scheme / 场景光斑。
      function applyTheme(next) {
        if (!next) return;
        window.__antisitTheme = next;
        var doc = document.documentElement;
        function set(name, value) {
          if (value) doc.style.setProperty(name, value);
        }
        set('--antisit-bg', next.bg);
        set('--antisit-card', next.card);
        if (next.card) set('--antisit-card-solid', over(next.card, next.bg));
        set('--antisit-card-elevated', next.cardElevated);
        set('--antisit-nav-pill', next.navPill);
        set('--antisit-menu-bg', next.menuBg);
        set('--antisit-border', next.border);
        set('--antisit-border-strong', next.borderStrong);
        set('--antisit-input-fill', next.inputFill);
        set('--antisit-stripe', next.stripe);
        set('--antisit-thumb', next.thumb);
        set('--antisit-overlay', next.overlay);
        set('--antisit-shadow', next.shadow);
        set('--antisit-fg', next.textPrimary);
        set('--antisit-text-secondary', next.textSecondary);
        set('--antisit-text-muted', next.textMuted);
        set('--antisit-accent', next.accent);
        set('--antisit-accent-soft', next.accentSoft);
        set('--antisit-accent-strong', next.accentStrong);
        set('--antisit-gold', next.gold);
        set('--antisit-gold-soft', next.goldSoft);
        set('--antisit-warning', next.warning || next.gold);
        set('--antisit-warning-soft', next.warningSoft || next.goldSoft);
        set('--antisit-success', next.success);
        set('--antisit-success-soft', next.successSoft);
        set('--antisit-danger', next.danger);
        set('--antisit-danger-soft', next.dangerSoft);
        set('--antisit-on-accent', next.onAccent);
        set('--antisit-radius-card', px(next.radiusCard));
        set('--antisit-radius-control', px(next.radiusControl));
        set('--antisit-radius-button', px(next.radiusButton));
        set('--antisit-radius-dialog', px(next.radiusDialog));
        set('--antisit-radius-sheet', px(next.radiusSheet));
        set('--antisit-radius-pill', px(next.radiusPill));
        set('--antisit-theme-id', next.themeId);
        var wells = wellsCss(next.wells);
        set('--antisit-wells', wells || 'none');
        doc.classList.toggle('dark', !!next.isDark);
        doc.style.colorScheme = next.isDark ? 'dark' : 'light';
        document.body.style.backgroundColor = next.bg || '';
        document.body.style.backgroundImage = wells || 'none';
        document.body.style.backgroundAttachment = 'fixed';
        document.body.style.color = next.textPrimary || '';
      }

      installDownloadHook();

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
    required String uiCss,
    required String uiJs,
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
    String safeStyle(String s) => s.replaceAll('</style', r'<\/style');
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
<style>${safeStyle(uiCss)}</style>
</head>
<body>
<div id="root"></div>
<div id="boot">正在启动「${_escapeHtml(item.name)}」…</div>
<script>${safeScript(kWebViewBridgeShim)}</script>
<script>${safeScript(uiJs)}</script>
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
