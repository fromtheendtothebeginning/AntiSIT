import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:campus_core/campus_core.dart';

/// 内核自带的整页浏览器：加载 [url] 或 [html]，带加载进度与出错提示。
/// 供 [WebViewCapabilityImpl.openPage] 推入导航栈。
class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key, this.url, this.html, this.title = ''});

  /// 二选一：[url] 优先；都为空就是空白页。
  final String? url;
  final String? html;
  final String title;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  double _progress = 0; // 0 = 没在加载
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => mounted ? setState(() => _progress = p / 100) : null,
        onWebResourceError: (e) {
          // 主文档失败才提示；子资源（图片等）失败不打扰
          if (e.isForMainFrame ?? false) {
            if (mounted) setState(() => _error = e.description);
          }
        },
      ));
    _load();
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
      await _controller.loadHtmlString(widget.html!);
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
