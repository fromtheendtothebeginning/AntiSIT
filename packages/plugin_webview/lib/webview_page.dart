import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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

/// 网页里的接口垫片由 [kWebViewBridgeShim] 提供；内核只在加载前后负责注入与回填。
class _WebViewPageState extends State<WebViewPage> implements WebBridgeEventSink {
  late final WebViewController _controller;
  double _progress = 0; // 0 = 没在加载
  String? _error;

  /// 网页下载交给 Android DownloadManager（见 `ExtWebViewFilesBridge.kt`）。
  /// DownloadListener 是挂在原生 WebView 上的，每个页面装一次即可。
  static const MethodChannel _webFilesChannel =
      MethodChannel('antisit/webview_files');
  bool _downloadListenerInstalled = false;

  /// 主框架当前地址（跨站导航后桥接能力要关掉，见 [bridgeAllowedOnPage]）。
  String? _currentUrl;

  /// 网页自己的页面栈是否还有页面（`ctx.ui.push` 叠上去没退完）。
  /// 为 true 时系统返回先让网页回退栈内页面，栈空才关整页。
  bool _hasStackPage = false;

  /// 这份内容是「内联 html」（压缩包拓展）还是「网址」——导航判定按它分岔。
  bool get _inline =>
      widget.html != null && (widget.url == null || widget.url!.trim().isEmpty);

  bool get _canUseBridge => bridgeAllowedOnPage(
        currentUrl: _currentUrl ?? widget.url,
        initialUrl: widget.url ?? '',
        fromInlineHtml: _inline,
      );

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(SemColors.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => mounted ? setState(() => _progress = p / 100) : null,
        onPageStarted: (url) => _currentUrl = url,
        onUrlChange: (change) => _currentUrl = change.url,
        onPageFinished: (_) {
          _injectBridge();
          _installDownloadListener();
        },
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
      widget.bridge!.attachEventSink(this);
      widget.bridge!.attachBackGuard(_onBackGuard);
    }
    unawaited(_configureFileChooser());
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _installDownloadListener());
    SemColors.palette.addListener(_onPaletteChanged);
    _load();
  }

  /// 主题 / 夜间模式切换：WebView 自身的底色也跟着换，页面切换时不会闪白。
  void _onPaletteChanged() {
    if (!mounted) return;
    unawaited(() async {
      try {
        await _controller.setBackgroundColor(SemColors.bg);
      } catch (_) {
        // 旧内核 / 平台不支持时忽略
      }
    }());
  }

  @override
  void dispose() {
    SemColors.palette.removeListener(_onPaletteChanged);
    widget.bridge?.attachEventSink(null);
    widget.bridge?.attachBackGuard(null);
    super.dispose();
  }

  /// 网页告诉我们它的页面栈空了没有。栈里还有页面时拦下系统返回，
  /// 先让它回退一层；否则保持默认行为（返回直接关掉这页）。
  void _onBackGuard(bool canGoBack) {
    if (!mounted || _hasStackPage == canGoBack) return;
    setState(() => _hasStackPage = canGoBack);
  }

  /// 系统返回 / 左上角返回箭头：先问网页能不能自己回退。
  /// 网页返回 false（或已经不在）才关掉整页，避免把用户困在拓展里。
  Future<void> _backFromStack() async {
    var handled = false;
    try {
      final value = await _controller.runJavaScriptReturningResult(
          'window.__antiSITBack ? window.__antiSITBack() : false');
      handled = value == true || value == 'true';
    } catch (_) {
      handled = false;
    }
    if (!handled && mounted) {
      setState(() => _hasStackPage = false);
      Navigator.of(context).pop();
    }
  }

  /// [WebBridgeEventSink]：App → 网页的下行事件（流式输出等）。
  @override
  void emit(String event, Object? data) {
    // 跨站页面不再持有桥接能力，流式 AI 的增量也不能再推过去。
    if (!_canUseBridge) return;
    unawaited(_controller
        .runJavaScript(
            'window.__antiSITEvent && window.__antiSITEvent(${jsonEncode(event)}, ${jsonEncode(data)})')
        .catchError((_) {}));
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

  /// 网页里的 `<input type=file>`：Android 走系统文件选择器，选完把文件 URI 交回
  /// WebView。上传兼容性只在这一层做，不给网页任何额外接口。
  Future<void> _configureFileChooser() async {
    final platform = _controller.platform;
    if (platform is! AndroidWebViewController) return;
    try {
      await platform.setOnShowFileSelector(_onShowFileSelector);
    } catch (_) {
      // 旧内核没有这个回调：网页上传保持不可用，不影响浏览
    }
  }

  Future<List<String>> _onShowFileSelector(FileSelectorParams params) async {
    if (params.mode == FileSelectorMode.save) return const [];
    final extensions = <String>{};
    final mimeTypes = <String>{};
    for (final raw in params.acceptTypes) {
      final value = raw.trim().toLowerCase();
      if (value.isEmpty) continue;
      if (value.startsWith('.')) {
        extensions.add(value.substring(1));
      } else if (value.contains('/')) {
        mimeTypes.add(value);
      }
    }
    final groups = <XTypeGroup>[
      if (extensions.isNotEmpty || mimeTypes.isNotEmpty)
        XTypeGroup(
          label: '文件',
          extensions: extensions.isEmpty ? null : extensions.toList(),
          mimeTypes: mimeTypes.isEmpty ? null : mimeTypes.toList(),
        ),
    ];
    try {
      final files = params.mode == FileSelectorMode.openMultiple
          ? await openFiles(acceptedTypeGroups: groups)
          : [if (await openFile(acceptedTypeGroups: groups) case final f?) f];
      return [for (final f in files) _fileUri(f.path)];
    } catch (_) {
      // 用户取消 / 选择器不可用：回空列表，网页收到一次空的 change
      return const [];
    }
  }

  /// file_selector 给的是本地路径；WebView 的 file chooser 要 URI。
  /// 已经带 scheme 的（content://）原样返回。
  static String _fileUri(String path) {
    final uri = Uri.tryParse(path);
    return uri != null && uri.hasScheme ? path : Uri.file(path).toString();
  }

  /// 挂原生下载监听：点击下载链接时交给系统 DownloadManager（通知栏进度 +
  /// 下载完成可点开），不在 WebView 里硬开一个二进制页面。
  Future<void> _installDownloadListener() async {
    if (_downloadListenerInstalled || !mounted) return;
    final platform = _controller.platform;
    if (platform is! AndroidWebViewController) return;
    try {
      final ok = await _webFilesChannel.invokeMethod<bool>(
        'installDownloadListener',
        {'id': platform.webViewIdentifier},
      );
      _downloadListenerInstalled = ok == true;
    } catch (_) {
      // 桌面 / iOS / 旧内核：保持默认行为
    }
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
          : injectBridgeShim(widget.html!, kWebViewBridgeShim);
      await _controller.loadHtmlString(html);
    }
  }

  /// 页面加载完成后注入垫片：网页里才有 `window.antiSIT` 可用。
  /// 只给拓展自己的页面注入；跨站导航后不注入（直接调通道的也会在 [_onBridgeCall] 被拒）。
  Future<void> _injectBridge() async {
    if (widget.bridge == null) return;
    if (!_canUseBridge) return;
    try {
      await _controller.runJavaScript(kWebViewBridgeShim);
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
      if (!_canUseBridge) {
        throw const FormatException('当前页面不在拓展的源内，接口不可用');
      }
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
    return PopScope<Object?>(
      // 栈里有页面时先拦下返回，交给网页自己的页面栈回退
      canPop: !_hasStackPage,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _backFromStack();
      },
      child: Scaffold(
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
      ),
    );
  }
}
