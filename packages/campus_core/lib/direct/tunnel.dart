import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 连校园内网站点的两条路 + 一个 TLS 补丁：直连（[connectDirect]）或经服务器隧道代理（[connectViaProxy]）。
///
/// 两种方式最后都走 [startNoSniTls]（带 SNI 会被教务的 Tengine reset），主机名由 [verifyHost] 自行核对。
class TunnelException implements Exception {
  const TunnelException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 直连 `host:port`。
Future<Socket> connectDirect(String host, int port,
    {Duration timeout = const Duration(seconds: 20)}) async {
  try {
    return await Socket.connect(host, port, timeout: timeout);
  } on SocketException catch (e) {
    throw TunnelException('连不上 $host：${e.message}');
  } on TimeoutException {
    throw TunnelException('连不上 $host：连接超时');
  }
}

/// 解析 `http://host:port` / `host:port` 形式的代理地址；解析不出来返回 null。
({String host, int port})? parseHttpProxy(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  s = s.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  s = s.split('/').first.replaceAll(RegExp(r'/+$'), '');
  final at = s.lastIndexOf('@');
  if (at > 0) s = s.substring(at + 1);
  final colon = s.lastIndexOf(':');
  if (colon <= 0) return null;
  final host = s.substring(0, colon).trim();
  final port = int.tryParse(s.substring(colon + 1).trim()) ?? 0;
  if (host.isEmpty || port <= 0) return null;
  return (host: host, port: port);
}

/// 经 HTTP 代理打 CONNECT 建隧道，返回**裸 TCP**（TLS 由调用方加）。
Future<Socket> connectViaProxy(
  String proxyUrl,
  String targetHost,
  int targetPort, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final proxy = parseHttpProxy(proxyUrl);
  if (proxy == null) {
    throw TunnelException('代理地址不对：$proxyUrl');
  }
  final socket = await connectDirect(proxy.host, proxy.port, timeout: timeout);
  try {
    final target = '$targetHost:$targetPort';
    socket.add(utf8.encode(
      'CONNECT $target HTTP/1.1\r\nHost: $target\r\nConnection: keep-alive\r\n\r\n',
    ));
    await socket.flush();
    final head = await readUntilHeaderEnd(socket, timeout: timeout);
    final statusLine = head.split('\r\n').first;
    final m = RegExp(r'HTTP/1\.[01] (\d{3})').firstMatch(statusLine);
    final status = m == null ? 0 : int.parse(m.group(1)!);
    if (status < 200 || status >= 300) {
      socket.destroy();
      throw TunnelException('代理拒绝连接 $targetHost（HTTP $status）');
    }
    return socket;
  } catch (e) {
    socket.destroy();
    if (e is TunnelException) rethrow;
    if (e is TimeoutException) {
      throw TunnelException('代理 $proxyUrl 建隧道超时');
    }
    throw TunnelException('经代理建隧道失败：$e');
  }
}

/// 从 socket 上读到 `\r\n\r\n` 为止（含）并返回该段文本。
///
/// 只暂停订阅、不取消：取消会让后面的 TLS 握手收不到应答，多余字节由调用方继续读。
Future<String> readUntilHeaderEnd(Socket socket,
    {Duration timeout = const Duration(seconds: 25)}) async {
  const separator = <int>[13, 10, 13, 10];
  final buffer = <int>[];
  final done = Completer<String>();
  late final StreamSubscription<Uint8List> sub;
  sub = socket.listen(
    (data) {
      buffer.addAll(data);
      final at = _indexOf(buffer, separator);
      if (at >= 0 && !done.isCompleted) {
        done.complete(utf8.decode(buffer.sublist(0, at), allowMalformed: true));
      }
    },
    onError: (Object e, StackTrace st) {
      if (!done.isCompleted) done.completeError(TunnelException('代理连接中断：$e'));
    },
    onDone: () {
      if (!done.isCompleted) done.completeError(const TunnelException('代理提前关闭了连接'));
    },
  );
  try {
    final head = await done.future.timeout(timeout);
    // 只是暂停：Dart 在最后一个订阅被取消时会 shutdown(receive)，后面的 TLS 就收不到应答
    sub.pause();
    return head;
  } on TimeoutException {
    await sub.cancel();
    throw const TunnelException('等待代理应答超时');
  } catch (e) {
    await sub.cancel();
    rethrow;
  }
}

int _indexOf(List<int> data, List<int> pattern) {
  outer:
  for (var i = 0; i + pattern.length <= data.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// 在已连好的 socket 上开 TLS，**不带 SNI**。
///
/// ⚠️ 必须传 [InternetAddress]：传字符串 IP 仍会被当成主机名发 SNI，服务端照样 reset。
Future<SecureSocket> startNoSniTls(
  Socket socket, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  try {
    return await SecureSocket.secure(
      socket,
      host: InternetAddress('10.0.0.1'),
      onBadCertificate: (_) => true,
    ).timeout(timeout);
  } on TimeoutException {
    socket.destroy();
    throw const TunnelException('校园网站点握手超时（隧道很慢，或学校站点在维护）');
  } on HandshakeException catch (e) {
    socket.destroy();
    throw TunnelException('校园网站点握手失败：${e.message}');
  }
}

/// 校验证书是否属于 [expected]（CN / SAN 里出现该域名，或其父域通配）。
///
/// [startNoSniTls] 不校验主机名，这一步是它的补丁：证书对不上就拒绝继续，别把密码发给不明服务端。
bool verifyHost(X509Certificate cert, String expected) {
  final want = expected.trim().toLowerCase();
  if (want.isEmpty) return true;
  final texts = <String>[cert.subject.toLowerCase()];
  try {
    final body = cert.pem
        .replaceAll(RegExp(r'-----[^-]+-----'), '')
        .replaceAll(RegExp(r'\s+'), '');
    texts.add(utf8.decode(base64Decode(body), allowMalformed: true).toLowerCase());
  } catch (_) {}
  for (final text in texts) {
    if (text.isEmpty) continue;
    if (text.contains(want)) return true;
    final dot = want.indexOf('.');
    if (dot > 0 && text.contains(want.substring(dot))) return true;
  }
  return false;
}