import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_error.dart';

/// 单次请求结果。[redirect]=false 时不跟随跳转，便于识别 302（登录失效 / SSO 握手）。
class HttpResult {
  HttpResult(this.status, this.url, this.body, this.headers);

  final int status;
  final String url;
  final Uint8List body;
  final Map<String, List<String>> headers;

  String get text => utf8.decode(body, allowMalformed: true);

  String get contentType =>
      (headers['content-type']?.isNotEmpty ?? false) ? headers['content-type']!.first : '';

  String get location =>
      (headers['location']?.isNotEmpty ?? false) ? headers['location']!.first : '';

  dynamic get json {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  bool get isImage => contentType.contains('image');
}

/// 直连校园系统用的 HTTP 会话：Cookie 罐（可按需持久化）+ 校内自签证书容忍 + 内网错误文案。
class HttpSession {
  HttpSession({required this.trustHosts, this.persistKey});

  /// 允许自签/校内 CA 证书的主机（后缀匹配）。
  final List<String> trustHosts;

  /// 非空时把 Cookie 存到 SharedPreferences（跨启动复用登录态）。
  final String? persistKey;

  late final http.Client _client = _buildClient();
  final Map<String, Map<String, String>> _jar = {};
  bool _loaded = false;

  http.Client _buildClient() {
    final io = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    io.badCertificateCallback = (_, host, __) => _trusted(host);
    return IOClient(io);
  }

  bool _trusted(String host) =>
      trustHosts.any((t) => t.isNotEmpty && (host == t || host.endsWith('.$t')));

  void dispose() => _client.close();

  // ==================== Cookie ====================

  String _cookieHeader(String host) {
    final parts = <String>[];
    _jar.forEach((domain, cookies) {
      if (host == domain || host.endsWith('.$domain')) {
        cookies.forEach((k, v) => parts.add('$k=$v'));
      }
    });
    return parts.join('; ');
  }

  void _storeCookies(String host, Map<String, List<String>> headers) {
    final raw = headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    var changed = false;
    for (final line in raw) {
      for (final one in line.split(RegExp(r',(?=[^;=]+=)'))) {
        final seg = one.split(';');
        if (seg.isEmpty) continue;
        final kv = seg.first.trim();
        final eq = kv.indexOf('=');
        if (eq <= 0) continue;
        final name = kv.substring(0, eq).trim();
        final value = kv.substring(eq + 1).trim();
        var domain = host;
        for (final attr in seg.skip(1)) {
          final a = attr.trim();
          if (a.toLowerCase().startsWith('domain=')) {
            domain = a.substring(7).trim().replaceFirst(RegExp(r'^\.'), '');
          }
        }
        if (domain.isEmpty) domain = host;
        (_jar[domain] ??= {})[name] = value;
        changed = true;
      }
    }
    if (changed) unawaited(persist());
  }

  void clearCookies() {
    _jar.clear();
    unawaited(persist());
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final key = persistKey;
    if (key == null) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(key);
      if (raw == null || raw.isEmpty) return;
      final obj = jsonDecode(raw);
      if (obj is Map) {
        obj.forEach((host, cookies) {
          if (cookies is Map) {
            _jar[host.toString()] = cookies.map((k, v) => MapEntry(k.toString(), v.toString()));
          }
        });
      }
    } catch (_) {}
  }

  Future<void> persist() async {
    final key = persistKey;
    if (key == null) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(key, jsonEncode(_jar));
    } catch (_) {}
  }

  // ==================== 请求 ====================

  Future<HttpResult> get(
    String url, {
    Map<String, String>? headers,
    bool redirect = true,
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _send('GET', url, headers: headers, redirect: redirect, timeout: timeout);

  Future<HttpResult> postForm(
    String url,
    Map<String, String> data, {
    Map<String, String>? headers,
    bool redirect = true,
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _send('POST', url,
          body: Uri(queryParameters: data).query,
          contentType: 'application/x-www-form-urlencoded;charset=UTF-8',
          headers: headers,
          redirect: redirect,
          timeout: timeout);

  Future<HttpResult> postJson(
    String url,
    Object? data, {
    Map<String, String>? headers,
    bool redirect = true,
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _send('POST', url,
          body: jsonEncode(data ?? {}),
          contentType: 'application/json',
          headers: headers,
          redirect: redirect,
          timeout: timeout);

  Future<HttpResult> _send(
    String method,
    String url, {
    String? body,
    String? contentType,
    Map<String, String>? headers,
    bool redirect = true,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // 自己跟随重定向：dart:io/http 自动跟随只把最后一跳的响应交出来，
    // 中间 302 上的 Set-Cookie（学校系统恰恰用它建会话）会被丢掉——会话对不上，
    // 验证码就绑到另一个会话上，登录必然失败。服务端 Python 用 requests 不会丢，
    // 所以这里手动跟，每一跳都收 Cookie。
    var currentUrl = url;
    var currentMethod = method;
    String? currentBody = body;
    String? currentType = contentType;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final uri = Uri.parse(currentUrl);
      final host = uri.host;
      await load(); // 首次请求前载入持久化 Cookie（跨启动复用登录态）
      final http.Response resp;
      try {
        final req = http.Request(currentMethod, uri);
        req.followRedirects = false;
        req.headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';
        // 与浏览器 / 服务端 requests 一致的常规头：学校系统前的 WAF 会挑没有 Accept 的请求
        req.headers['Accept'] = '*/*';
        req.headers['Accept-Language'] = 'zh-CN,zh;q=0.9';
        final cookie = _cookieHeader(host);
        if (cookie.isNotEmpty) req.headers['Cookie'] = cookie;
        if (currentType != null) req.headers['Content-Type'] = currentType;
        if (headers != null) req.headers.addAll(headers);
        if (currentBody != null) req.body = currentBody;
        final streamed = await _client.send(req).timeout(timeout);
        resp = await http.Response.fromStream(streamed).timeout(timeout);
      } on ApiError {
        rethrow;
      } on TimeoutException {
        throw ApiError(_netHint(host, '连接超时'));
      } on SocketException {
        throw ApiError(_netHint(host, '无法连接'));
      } on HttpException {
        throw ApiError(_netHint(host, '无法连接'));
      } catch (e) {
        throw ApiError('访问学校系统失败（$host）：$e');
      }
      _storeCookies(host, resp.headersSplitValues);
      final location = resp.headersSplitValues['location']?.first ?? '';
      if (!redirect || location.isEmpty || !_isRedirect(resp.statusCode)) {
        return HttpResult(
            resp.statusCode, uri.toString(), resp.bodyBytes, resp.headersSplitValues);
      }
      // 302/303 跟随时改 GET 并丢掉请求体（浏览器与 requests 的默认行为）
      if (resp.statusCode == 303 ||
          ((resp.statusCode == 301 || resp.statusCode == 302) && currentMethod != 'GET')) {
        currentMethod = 'GET';
        currentBody = null;
        currentType = null;
      }
      currentUrl = uri.resolve(location).toString();
    }
    throw ApiError('学校系统（$url）重定向次数过多，请核对该校系统地址是否配置正确');
  }

  static const int _maxRedirects = 10;

  static bool _isRedirect(int status) =>
      status == 301 || status == 302 || status == 303 || status == 307 || status == 308;

  /// 直连模式的网络失败提示：把「内网要求」讲清楚（服务器模式才有 VPN 代连）。
  static String _netHint(String host, String what) =>
      '$what学校系统（$host）：直连模式不走服务器，请确认设备已连接校园网 / 校内 VPN 后重试';
}
