/// 拓展的原生 HTTPS 代理：给网页一个不受 CORS 限制、可以自己带 Cookie 头的请求口。
///
/// 为什么不让网页直接 `fetch`：拓展页是 `loadHtmlString` 的 opaque origin，
/// 跨域请求受 CORS 限制，而且 `fetch` 不允许设置 `Cookie` 头。学校系统这类
/// 需要登录态的接口只能走原生发。
///
/// 这是通用能力，不包含任何学校专用逻辑；App 不解析响应，只把文本回给拓展。
/// 安全约束：
/// * 只允许 https；
/// * 拒绝 localhost / 内网 / 链路本地 / 保留地址（防 SSRF）；
/// * 过滤 Host / Content-Length / Connection 这类由底层接管的头；
/// * 响应最多 2 MB，超时 30 秒。
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

  /// 发起一次请求。返回 `{status, url, headers, setCookies, text, truncated, bytes}`。
  ///
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
      HttpClientResponse response, Uri uri, List<String> setCookies) async {
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
      'text': utf8.decode(bytes, allowMalformed: true),
      'truncated': truncated,
      'bytes': bytes.length,
    };
  }
}
