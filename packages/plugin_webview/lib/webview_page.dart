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

/// 内核自带的整页浏览器：加载 [url] 或 [html]，带加载进度与出错提示；供 [WebViewCapabilityImpl.openPage] 推入导航栈。
/// 带 [bridge] 时注入网页 ↔ App 通道（垫片 `antiSIT` + 原始通道 `antiSITBridge` + Promise 回填）。
/// **导航**：内联 html（压缩包拓展）的主框架只许走本地方案，点到 http(s) 外链交系统浏览器；网址形态正常浏览。
class WebViewPage extends StatefulWidget {
  const WebViewPage({
    super.key,
    this.url,
    this.html,
    this.title = '',
    this.bridge,
    this.proxy = '',
  });

  /// 二选一：[url] 优先；都为空就是空白页。
  final String? url;
  final String? html;
  final String title;

  /// 非空时注入 JS 通道（见 [WebBridge]）。
  final WebBridge? bridge;

  /// HTTP 代理（http://host:port）：服务器模式下打开只有校园内网能到的网页时用
  /// （融合门户这类）。空 = 直连。代理是进程级的，离开本页必须清掉。
  final String proxy;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

/// 网页里的接口垫片由 [kWebViewBridgeShim] 提供；内核只在加载前后负责注入与回填。
class _WebViewPageState extends State<WebViewPage>
    implements WebBridgeEventSink {
  late final WebViewController _controller;
  double _progress = 0; // 0 = 没在加载
  String? _error;

  /// 网页下载交给 Android DownloadManager（见 `ExtWebViewFilesBridge.kt`）；
  /// DownloadListener 挂在原生 WebView 上，每个页面装一次即可。
  static const MethodChannel _webFilesChannel = MethodChannel(
    'antisit/webview_files',
  );

  /// 代理是进程级的（Android WebView ProxyController，见 `WebViewProxyBridge.kt`）：
  /// 设过就必须在本页销毁时清掉，否则后面所有 WebView 都还在走校园隧道。
  static const MethodChannel _proxyChannel = MethodChannel('antisit/webview');
  bool _proxyApplied = false;
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
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) =>
              mounted ? setState(() => _progress = p / 100) : null,
          onPageStarted: (url) => _currentUrl = url,
          onUrlChange: (change) => _currentUrl = change.url,
          onPageFinished: (_) {
            _injectBridge();
            _installDownloadListener();
          },
          onNavigationRequest: _onNavigationRequest,
          onWebResourceError: (e) {
            // 主文档失败才提示；子资源（图片等）失败不打扰。
            if (e.isForMainFrame ?? false) {
              if (mounted) setState(() => _error = e.description);
            }
          },
        ),
      );
    if (widget.bridge != null) {
      _controller.addJavaScriptChannel(
        'antiSITBridge',
        onMessageReceived: _onBridgeCall,
      );
      widget.bridge!.attachEventSink(this);
      widget.bridge!.attachBackGuard(_onBackGuard);
    }
    unawaited(_configureFileChooser());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _installDownloadListener(),
    );
    SemColors.palette.addListener(_onPaletteChanged);
    unawaited(_boot());
  }

  /// 首次加载：代理必须在第一个请求之前设好——ProxyController 是进程级的，
  /// 设晚了首个请求已经直连出去，只有内网能到的站点就直接报加载失败。
  Future<void> _boot() async {
    await _applyProxy();
    if (mounted) await _load();
  }

  Future<void> _applyProxy() async {
    if (widget.proxy.isEmpty) return;
    try {
      final ok = await _proxyChannel.invokeMethod<bool>('setProxy', {
        'url': widget.proxy,
      });
      _proxyApplied = ok == true;
      if (!_proxyApplied) {
        debugPrint('[WebViewPage] 当前内核不支持网页代理，按直连处理');
      }
    } catch (e) {
      // iOS / 桌面端没有这条通道：保持直连，页面自己会给出加载失败。
      debugPrint('[WebViewPage] 设置代理失败：$e');
    }
  }

  /// 主题 / 夜间模式切换：WebView 自身的底色也跟着换，页面切换时不会闪白。
  void _onPaletteChanged() {
    if (!mounted) return;
    unawaited(() async {
      try {
        await _controller.setBackgroundColor(SemColors.bg);
      } catch (_) {
        // 旧内核 / 平台不支持时忽略。
      }
    }());
  }

  @override
  void dispose() {
    SemColors.palette.removeListener(_onPaletteChanged);
    widget.bridge?.attachEventSink(null);
    widget.bridge?.attachBackGuard(null);
    // 代理是进程级的：不恢复的话，离开本页后其它 WebView 也会继续走校园隧道。
    if (_proxyApplied) {
      unawaited(() async {
        try {
          await _proxyChannel.invokeMethod('setProxy', {'url': null});
        } catch (_) {}
      }());
    }
    super.dispose();
  }

  /// 网页告诉我们它的页面栈空了没有：还有页面时拦下系统返回，先让它回退一层。
  void _onBackGuard(bool canGoBack) {
    if (!mounted || _hasStackPage == canGoBack) return;
    setState(() => _hasStackPage = canGoBack);
  }

  /// 系统返回 / 左上角返回箭头：先问网页能不能自己回退，不能才关掉整页。
  Future<void> _backFromStack() async {
    var handled = false;
    try {
      final value = await _controller.runJavaScriptReturningResult(
        'window.__antiSITBack ? window.__antiSITBack() : false',
      );
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
    unawaited(
      _controller
          .runJavaScript(
            'window.__antiSITEvent && window.__antiSITEvent(${jsonEncode(event)}, ${jsonEncode(data)})',
          )
          .catchError((_) {}),
    );
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

  /// 网页里的 `<input type=file>`：Android 走系统文件选择器，选完把文件 URI 交回 WebView。
  Future<void> _configureFileChooser() async {
    final platform = _controller.platform;
    if (platform is! AndroidWebViewController) return;
    try {
      await platform.setOnShowFileSelector(_onShowFileSelector);
    } catch (_) {
      // 旧内核没有这个回调：网页上传保持不可用，不影响浏览。
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
      // 用户取消 / 选择器不可用：回空列表，网页收到一次空的 change。
      return const [];
    }
  }

  /// file_selector 给的是本地路径，WebView 的 file chooser 要 URI；已带 scheme 的原样返回。
  static String _fileUri(String path) {
    final uri = Uri.tryParse(path);
    return uri != null && uri.hasScheme ? path : Uri.file(path).toString();
  }

  /// 挂原生下载监听：点击下载链接交给系统 DownloadManager（通知栏进度 + 可点开），不在 WebView 里开二进制页面。
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
      // 桌面 / iOS / 旧内核：保持默认行为。
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
      // 内联页：垫片写进 html 本身，网页第一个同步脚本就能用 antiSIT。
      final html = widget.bridge == null
          ? widget.html!
          : injectBridgeShim(widget.html!, kWebViewBridgeShim);
      await _controller.loadHtmlString(html);
    }
  }

  /// 页面加载完成后注入垫片：网页里才有 `window.antiSIT`；跨站导航后不注入，
  /// 直接调通道的也会在 [_onBridgeCall] 被拒。
  Future<void> _injectBridge() async {
    if (widget.bridge == null) return;
    if (!_canUseBridge) return;
    try {
      await _controller.runJavaScript(kWebViewBridgeShim);
    } catch (_) {
      // 注入失败（页面拒绝执行脚本之类）不该把整页搞崩：网页仍可正常使用。
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
      // 分发出错（未知方法 / 参数不对）也要回给网页，否则它的 Promise 永远悬着。
      await _reply('__antiSITReject', id, '$e');
    }
  }

  Future<void> _reply(String fn, Object? id, Object? payload) async {
    try {
      await _controller.runJavaScript(
        'window.$fn(${jsonEncode(id)}, ${jsonEncode(payload)})',
      );
    } catch (_) {
      // 页面已经走了：没人接就没人接。
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      // 栈里有页面时先拦下返回，交给网页自己的页面栈回退。
      canPop: !_hasStackPage,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _backFromStack();
      },
      child: ListenableBuilder(
        listenable: AppState.I,
        builder: (context, _) {
          // 先算顶栏留白：body 里的 MediaQuery 已扣掉状态栏。
          final topInset = glassTopInset(context);
          return Scaffold(
            extendBodyBehindAppBar: glassTopBarEnabled,
            appBar: glassAppBar(
              context,
              title: Text(
                widget.title.isEmpty ? '网页' : widget.title,
                overflow: TextOverflow.ellipsis,
              ),
              // 加载进度条是顶栏的 bottom。
              bottom: _progress > 0 && _progress < 1
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(2),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 2,
                      ),
                    )
                  : null,
            ),
            // 平台视图不滚动：用 Padding 把网页从悬浮顶栏下面顶出来。
            body: GlassFadedBody(
              barHeight: topInset,
              child: Padding(
                padding: EdgeInsets.only(top: topInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Material(
                        color: SemColors.dangerSoft,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              fontSize: 12,
                              color: SemColors.danger,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    Expanded(child: WebViewWidget(controller: _controller)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
