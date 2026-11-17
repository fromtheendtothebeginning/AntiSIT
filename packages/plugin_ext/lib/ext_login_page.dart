/// 通用登录页：打开拓展给的一个 https 登录地址，登录完成后只返回它声明的那些域的 Cookie。
///
/// 页面是可见的：地址栏下面会显示当前域名，用户能看清自己在哪个站点登录。
/// 是否允许打开由 `ExtConsentService` 在进入前弹窗确认。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'ext_cookie_bridge.dart';

class ExtLoginPage extends StatefulWidget {
  const ExtLoginPage({
    super.key,
    required this.title,
    required this.startUrl,
    required this.cookieUrls,
    this.successUrlPrefix,
    this.successCookie,
    this.userAgent,
  });

  final String title;
  final String startUrl;
  final List<String> cookieUrls;

  /// 命中这个前缀 + [successCookie] 时自动完成；两个都不给就等用户点「完成」。
  final String? successUrlPrefix;
  final String? successCookie;
  final String? userAgent;

  /// 只接受 https，且不带账号密码。
  static Uri parseHttpsUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) {
      throw const FormatException('登录地址不是合法网址');
    }
    if (uri.scheme != 'https') {
      throw const FormatException('登录地址必须是 https');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const FormatException('登录地址里不要带账号密码');
    }
    return uri;
  }

  /// 同站判断：比较可注册域名。除了常见的两段域名，还覆盖 `.edu.cn` 这类
  /// 公共后缀——否则 `a.edu.cn` 和 `b.edu.cn` 会被误判为同站。
  static bool sameSite(String a, String b) {
    final x = _registrable(a.toLowerCase());
    final y = _registrable(b.toLowerCase());
    return x.isNotEmpty && x == y;
  }

  static const Set<String> _multiLabelSuffixes = {
    'edu.cn',
    'com.cn',
    'net.cn',
    'org.cn',
    'gov.cn',
    'co.uk',
    'ac.uk',
    'com.hk',
    'edu.hk',
    'com.tw',
    'edu.tw',
  };

  static String _registrable(String host) {
    final parts = host.split('.').where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) return host;
    for (final suffix in _multiLabelSuffixes) {
      final suffixParts = suffix.split('.');
      final n = suffixParts.length;
      if (parts.length > n &&
          parts.sublist(parts.length - n).join('.') == suffix) {
        return parts.sublist(parts.length - n - 1).join('.');
      }
    }
    return parts.sublist(parts.length - 2).join('.');
  }

  @override
  State<ExtLoginPage> createState() => _ExtLoginPageState();
}

class _ExtLoginPageState extends State<ExtLoginPage> {
  late final WebViewController _controller;
  double _progress = 0;
  String _host = '';
  bool _capturing = false;
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    _host = Uri.tryParse(widget.startUrl)?.host ?? '';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    if (widget.userAgent != null && widget.userAgent!.isNotEmpty) {
      _controller.setUserAgent(widget.userAgent!);
    }
    _controller.setNavigationDelegate(NavigationDelegate(
      onProgress: (value) {
        if (mounted) setState(() => _progress = value / 100);
      },
      onPageFinished: (url) {
        final host = Uri.tryParse(url)?.host ?? '';
        if (mounted && host.isNotEmpty && host != _host) {
          setState(() => _host = host);
        }
        unawaited(_tryCapture(url));
      },
    ));
    _controller.loadRequest(Uri.parse(widget.startUrl));
  }

  bool get _autoDetect =>
      (widget.successUrlPrefix?.isNotEmpty ?? false) ||
      (widget.successCookie?.isNotEmpty ?? false);

  Future<void> _tryCapture(String url) async {
    if (!_autoDetect || _captured || _capturing || !mounted) return;
    final prefix = widget.successUrlPrefix;
    final hasCookieRule = widget.successCookie?.isNotEmpty ?? false;
    if (prefix != null &&
        prefix.isNotEmpty &&
        !url.startsWith(prefix) &&
        !hasCookieRule) {
      return;
    }
    await _capture(auto: true);
  }

  Future<void> _finish() => _capture(auto: false);

  Future<void> _capture({required bool auto}) async {
    if (_capturing || !mounted) return;
    _capturing = true;
    try {
      final byUrl = await ExtCookieBridge.read(widget.cookieUrls);
      final header =
          ExtCookieBridge.mergeHeaders(byUrl, widget.cookieUrls);
      if (header.isEmpty) {
        if (!auto) _toast('还没拿到 Cookie，请先在页面里完成登录');
        return;
      }
      final required = widget.successCookie;
      if (required != null &&
          required.isNotEmpty &&
          !header.contains('$required=')) {
        if (!auto) _toast('还没检测到 $required，请确认已经登录成功');
        return;
      }
      _captured = true;
      if (mounted) {
        Navigator.of(context).pop(<String, Object?>{
          'cookies': byUrl,
          'cookieHeader': header,
        });
      }
    } catch (e) {
      if (!auto) _toast('读取 Cookie 失败：$e');
    } finally {
      _capturing = false;
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(onPressed: _finish, child: const Text('完成')),
        ],
      ),
      body: Column(
        children: [
          if (_progress > 0 && _progress < 1)
            LinearProgressIndicator(value: _progress, minHeight: 2),
          Expanded(child: WebViewWidget(controller: _controller)),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '当前站点：$_host',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '登录完成后只把这里声明的域名的 Cookie 交给拓展；App 不保存账号密码。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
