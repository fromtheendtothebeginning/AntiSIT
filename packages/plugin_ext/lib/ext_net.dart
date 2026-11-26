/// 拓展的原生 HTTPS 代理：给网页一个不受 CORS 限制、可以自己带 Cookie 头的请求口
/// （拓展页是 `loadHtmlString` 的 opaque origin，`fetch` 受 CORS 限制且不能设 Cookie 头）。
///
/// 默认只允许 https、拒绝 localhost / 内网 / 保留地址（防 SSRF）、响应上限 2 MB、
/// 超时 30 秒；`net.campus` 例外：只允许 http、可打内网但仍拒本机 / 回环 / CGNAT，
/// 可带校园隧道代理、不跟随重定向。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

class ExtNetException implements Exception {
  const ExtNetException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ExtNetService {
  ExtNetService._();

  static final ExtNetService I = ExtNetService._();

  static const Duration timeout = Duration(seconds: 30);
  static const int maxBodyBytes = 2 * 1024 * 1024;

  static const Set<String> _methods = {
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
    'OPTIONS',
  };

  /// 由 HttpClient 自己管理，拓展传了也不能用。
  static const Set<String> _blockedHeaders = {
    'host',
    'content-length',
    'connection',
    'transfer-encoding',
    'upgrade',
    'proxy-authorization',
  };

  /// 发起一次请求，返回 `{status, url, headers, setCookies, text, truncated, bytes}`；
  /// [onHost] 在每个新域名（含重定向）发出前调用一次，宿主用它做逐域授权。
  Future<Map<String, Object?>> request(
    Map<String, Object?> args, {
    Future<void> Function(String host)? onHost,
  }) async {
    final method = '${args['method'] ?? 'GET'}'.toUpperCase();
    if (!_methods.contains(method)) {
      throw ExtNetException('不支持的方法：$method');
    }
    final headers = sanitizeHeaders(args['headers']);
    headers.putIfAbsent(HttpHeaders.userAgentHeader, () => 'AntiSIT-Ext/1.0');
    final body = _bodyBytes(args);

    var uri = await validateUrl('${args['url'] ?? ''}');
    await onHost?.call(uri.host);
    final client = HttpClient()..connectionTimeout = timeout;
    final setCookies = <String>[];
    try {
      for (var hop = 0; hop <= 5; hop++) {
        final request = await client.openUrl(method, uri).timeout(timeout);
        request.followRedirects = false;
        headers.forEach(request.headers.set);
        if (body != null && method != 'GET' && method != 'HEAD') {
          request.contentLength = body.length;
          request.add(body);
        }
        final response = await request.close().timeout(timeout);
        setCookies.addAll(
            response.headers[HttpHeaders.setCookieHeader] ?? const []);
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (response.statusCode >= 300 &&
            response.statusCode < 400 &&
            location != null &&
            location.isNotEmpty) {
          await response.drain<void>();
          uri = await validateUrl(uri.resolve(location).toString());
          await onHost?.call(uri.host);
          continue;
        }
        return await _readResponse(response, uri, setCookies);
      }
      throw const ExtNetException('重定向次数过多');
    } on TimeoutException {
      throw const ExtNetException('请求超时');
    } on SocketException catch (e) {
      throw ExtNetException('连接失败：${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  /// 校内明文通道 `net.campus`：与 [request] 的区别是只允许 http、目标可以是内网
  /// （仍拒绝本机 / 回环 / 链路本地 / CGNAT）、可带 [proxyUrl] 隧道代理、不跟随重定向。
  Future<Map<String, Object?>> campusRequest(
    Map<String, Object?> args, {
    Future<void> Function(String host)? onHost,
  }) async {
    final method = '${args['method'] ?? 'GET'}'.toUpperCase();
    if (!_methods.contains(method)) {
      throw ExtNetException('不支持的方法：$method');
    }
    final headers = sanitizeHeaders(args['headers']);
    headers.putIfAbsent(HttpHeaders.userAgentHeader, () => 'AntiSIT-Ext/1.0');
    final body = _bodyBytes(args);

    final uri = await validateCampusUrl('${args['url'] ?? ''}');
    await onHost?.call(uri.host);

    final proxyUrl = '${args['proxy'] ?? ''}'.trim();
    final asBase64 = '${args['responseEncoding'] ?? ''}'.trim() == 'base64';
    if (proxyUrl.isEmpty) {
      return _campusDirect(method, uri, headers, body, asBase64: asBase64);
    }
    return _campusViaProxy(proxyUrl, method, uri, headers, body, asBase64: asBase64);
  }

  /// 直连：设备自己在校园网里时走这条。
  Future<Map<String, Object?>> _campusDirect(
    String method,
    Uri uri,
    Map<String, String> headers,
    Uint8List? body, {
    bool asBase64 = false,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      if (body != null && method != 'GET' && method != 'HEAD') {
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close().timeout(timeout);
      final setCookies = <String>[
        ...?response.headers[HttpHeaders.setCookieHeader],
      ];
      return await _readResponse(response, uri, setCookies, asBase64: asBase64);
    } on TimeoutException {
      throw const ExtNetException('请求超时');
    } on SocketException catch (e) {
      throw ExtNetException('连接失败：${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  /// 经校园隧道代理：手写 HTTP/1.1（隧道代理只认绝对 URI 的明文转发）。
  Future<Map<String, Object?>> _campusViaProxy(
    String proxyUrl,
    String method,
    Uri uri,
    Map<String, String> headers,
    Uint8List? body, {
    bool asBase64 = false,
  }) async {
    final proxy = parseProxyUrl(proxyUrl);
    if (proxy == null) {
      throw ExtNetException('隧道代理地址不对：$proxyUrl');
    }
    Socket socket;
    try {
      socket = await Socket.connect(proxy.host, proxy.port, timeout: timeout);
    } on SocketException catch (e) {
      throw ExtNetException('连不上隧道代理 ${proxy.host}：${e.message}');
    }
    try {
      socket.add(utf8.encode(buildProxyHead(
        method: method,
        uri: uri,
        headers: headers,
        contentLength:
            body != null && method != 'GET' && method != 'HEAD' ? body.length : null,
      )));
      if (body != null && method != 'GET' && method != 'HEAD') socket.add(body);
      await socket.flush();

      final chunks = <int>[];
      await for (final chunk in socket) {
        chunks.addAll(chunk);
        if (chunks.length > maxBodyBytes + 64 * 1024) break;
      }
      return parseProxyResponse(Uint8List.fromList(chunks), uri, asBase64: asBase64);
    } on TimeoutException {
      throw const ExtNetException('请求超时');
    } on SocketException catch (e) {
      throw ExtNetException('隧道代理连接中断：${e.message}');
    } finally {
      socket.destroy();
    }
  }

  /// 拼一份经 HTTP 代理的请求头。**必须用 absolute-form**
  /// （`POST http://host:port/path HTTP/1.1`）：写成路径形式会被代理直接回 400。
  @visibleForTesting
  static String buildProxyHead({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    int? contentLength,
  }) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    final target = uri.hasQuery ? '$path?${uri.query}' : path;
    final lines = <String>[
      '$method ${uri.scheme}://${uri.host}:${uri.port}$target HTTP/1.1',
      'Host: ${uri.host}:${uri.port}',
      ...headers.entries.map((e) => '${e.key}: ${e.value}'),
      'Connection: close',
      if (contentLength != null) 'Content-Length: $contentLength',
    ];
    return '${lines.join('\r\n')}\r\n\r\n';
  }

  /// 解析代理回给我们的原始 HTTP 响应（没有 chunked 的隧道代理都是这种）。
  @visibleForTesting
  static Map<String, Object?> parseProxyResponse(
    Uint8List bytes,
    Uri uri, {
    bool asBase64 = false,
  }) {
    final split = _indexOfHeaderEnd(bytes);
    if (split < 0) throw const ExtNetException('代理没有返回完整的 HTTP 响应');
    final head = utf8.decode(bytes.sublist(0, split), allowMalformed: true);
    final headLines = head.split('\r\n');
    final status = int.tryParse(
          RegExp(r'HTTP/1\.[01] (\d{3})').firstMatch(headLines.first)?.group(1) ?? '',
        ) ??
        0;
    if (status == 0) {
      throw ExtNetException('代理返回了看不懂的响应：${headLines.first}');
    }
    final respHeaders = <String, String>{};
    final setCookies = <String>[];
    for (final line in headLines.skip(1)) {
      final at = line.indexOf(':');
      if (at <= 0) continue;
      final name = line.substring(0, at).trim();
      final value = line.substring(at + 1).trim();
      if (name.toLowerCase() == 'set-cookie') {
        setCookies.add(value);
      } else {
        respHeaders[name] = respHeaders.containsKey(name)
            ? '${respHeaders[name]}, $value'
            : value;
      }
    }
    var payload = bytes.sublist(split + 4);
    final truncated = payload.length > maxBodyBytes;
    if (truncated) payload = payload.sublist(0, maxBodyBytes);
    return {
      'status': status,
      'url': uri.toString(),
      'headers': respHeaders,
      'setCookies': setCookies,
      'text': asBase64
          ? base64Encode(payload)
          : utf8.decode(payload, allowMalformed: true),
      'truncated': truncated,
      'bytes': payload.length,
    };
  }

  static int _indexOfHeaderEnd(Uint8List bytes) {
    for (var i = 3; i < bytes.length; i++) {
      if (bytes[i - 3] == 13 &&
          bytes[i - 2] == 10 &&
          bytes[i - 1] == 13 &&
          bytes[i] == 10) {
        return i - 3;
      }
    }
    return -1;
  }

  /// 解析 `http://host:port` / `host:port`；解析不出来返回 null。
  @visibleForTesting
  static ({String host, int port})? parseProxyUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    s = s.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    s = s.split('/').first.replaceAll(RegExp(r'/+$'), '');
    final colon = s.lastIndexOf(':');
    if (colon <= 0) return null;
    final host = s.substring(0, colon).trim();
    final port = int.tryParse(s.substring(colon + 1).trim()) ?? 0;
    if (host.isEmpty || port <= 0 || port > 65535) return null;
    return (host: host, port: port);
  }

  /// 校内地址：只允许 http，且主机解析出来不能是本机 / 回环 / 链路本地 / CGNAT。
  Future<Uri> validateCampusUrl(String raw) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) {
      throw const ExtNetException('url 不是合法网址');
    }
    if (uri.scheme != 'http') {
      throw const ExtNetException('校内通道只接受 http（校内站点没有证书）');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const ExtNetException('url 里不要带账号密码');
    }
    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host == 'metadata.google.internal') {
      throw const ExtNetException('不允许访问本机 / 内网地址');
    }
    List<InternetAddress> addresses;
    try {
      addresses = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const ExtNetException('域名解析超时');
    } on SocketException {
      throw const ExtNetException('域名解析失败');
    }
    if (addresses.isEmpty) {
      throw const ExtNetException('域名解析失败');
    }
    for (final address in addresses) {
      if (isLoopbackOrLinkLocal(address)) {
        throw const ExtNetException('不允许访问本机 / 回环 / 链路本地地址');
      }
    }
    return uri;
  }

  /// 校内通道仍然拒绝的那几类地址：本机、回环、链路本地、CGNAT、组播。
  @visibleForTesting
  static bool isLoopbackOrLinkLocal(InternetAddress address) {
    final bytes = address.rawAddress;
    if (bytes.length == 16) {
      if (bytes.take(15).every((b) => b == 0) && bytes[15] == 1) return true;
      if ((bytes[0] & 0xfe) == 0xfc) return true;
      if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return true;
      if (bytes.take(10).every((b) => b == 0) &&
          bytes[10] == 0xff &&
          bytes[11] == 0xff) {
        return isLoopbackOrLinkLocal(InternetAddress.fromRawAddress(
          Uint8List.fromList(bytes.sublist(12)),
        ));
      }
      return false;
    }
    if (bytes.length != 4) return true;
    final a = bytes[0], c = bytes[1];
    if (a == 0 || a == 127 || a >= 224) return true;
    if (a == 169 && c == 254) return true;
    if (a == 100 && c >= 64 && c <= 127) return true;
    return false;
  }

  /// 只允许 https，并拒绝指向本机 / 内网的地址。重定向后的地址会再校验一次。
  Future<Uri> validateUrl(String raw) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) {
      throw const ExtNetException('url 不是合法网址');
    }
    if (uri.scheme != 'https') {
      throw const ExtNetException('只允许 https');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const ExtNetException('url 里不要带账号密码');
    }
    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host == 'metadata.google.internal') {
      throw const ExtNetException('不允许访问本机 / 内网地址');
    }

    List<InternetAddress> addresses;
    try {
      addresses = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const ExtNetException('域名解析超时');
    } on SocketException {
      throw const ExtNetException('域名解析失败');
    }
    if (addresses.isEmpty) {
      throw const ExtNetException('域名解析失败');
    }
    for (final address in addresses) {
      if (isBlockedAddress(address)) {
        throw const ExtNetException('不允许访问本机 / 内网地址');
      }
    }
    return uri;
  }

  /// 过滤掉底层接管的请求头。
  @visibleForTesting
  static Map<String, String> sanitizeHeaders(Object? raw) {
    final out = <String, String>{};
    if (raw is! Map) return out;
    raw.forEach((key, value) {
      final name = '$key'.trim();
      if (name.isEmpty) return;
      if (_blockedHeaders.contains(name.toLowerCase())) return;
      out[name] = '$value';
    });
    return out;
  }

  /// 本机 / 内网 / 链路本地 / 保留地址一律拒绝。
  @visibleForTesting
  static bool isBlockedAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (bytes.length == 4) return _isBlockedV4(bytes);
    if (bytes.length == 16) {
      // ::1
      if (bytes.take(15).every((b) => b == 0) && bytes[15] == 1) return true;
      // fc00::/7
      if ((bytes[0] & 0xfe) == 0xfc) return true;
      // fe80::/10
      if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return true;
      // ::ffff:x.x.x.x
      if (bytes.take(10).every((b) => b == 0) &&
          bytes[10] == 0xff &&
          bytes[11] == 0xff) {
        return _isBlockedV4(bytes.sublist(12));
      }
      return false;
    }
    return true;
  }

  static bool _isBlockedV4(List<int> b) {
    if (b.length != 4) return true;
    final a = b[0];
    final c = b[1];
    final d = b[2];
    if (a == 0 || a == 10 || a == 127) return true;
    if (a == 169 && c == 254) return true;
    if (a == 172 && c >= 16 && c <= 31) return true;
    if (a == 192 && c == 168) return true;
    if (a == 100 && c >= 64 && c <= 127) return true; // CGNAT
    if (a == 192 && c == 0 && (d == 0 || d == 2)) return true;
    if (a == 198 && (c == 18 || c == 19 || c == 51)) return true;
    if (a == 203 && c == 0 && d == 113) return true;
    if (a >= 224) return true;
    return false;
  }

  static Uint8List? _bodyBytes(Map<String, Object?> args) {
    final encoded = args['bodyBase64'];
    if (encoded is String && encoded.trim().isNotEmpty) {
      try {
        return base64Decode(encoded.trim());
      } catch (_) {
        throw const ExtNetException('bodyBase64 不是合法 base64');
      }
    }
    final text = args['body'];
    if (text == null) return null;
    return Uint8List.fromList(utf8.encode('$text'));
  }

  static Future<Map<String, Object?>> _readResponse(
      HttpClientResponse response,
      Uri uri,
      List<String> setCookies, {
      bool asBase64 = false,
    }) async {
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    final builder = BytesBuilder(copy: false);
    var truncated = false;
    await for (final chunk in response) {
      if (builder.length + chunk.length > maxBodyBytes) {
        truncated = true;
        break;
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    return {
      'status': response.statusCode,
      'url': uri.toString(),
      'headers': headers,
      'setCookies': setCookies,
      // 验证码图片这类二进制内容用 base64 回传（text 在 UTF-8 下会变成乱码）
      'text': asBase64
          ? base64Encode(bytes)
          : utf8.decode(bytes, allowMalformed: true),
      'truncated': truncated,
      'bytes': bytes.length,
    };
  }
}
