import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// SOCKS5 代理配置（RFC 1928）。
///
/// **凭据不进仓库、也不编译进 App**：地址与账号由使用者在「学生评教 → 校园代理」里填一次，
/// 存在本机加密存储里（见 plugin_evaluate 的 EvaluateSettings）；内部构建可用
/// `--dart-define=ANTISIT_EVAL_PROXY=host:port` 注入默认值——那只进二进制，不进 git。
class SocksProxy {
  const SocksProxy({
    required this.host,
    required this.port,
    this.username = '',
    this.password = '',
  });

  final String host;
  final int port;
  final String username;
  final String password;

  bool get isConfigured => host.trim().isNotEmpty && port > 0;
  bool get hasAuth => username.isNotEmpty;

  /// 未配置的代理（直连）。
  static const SocksProxy none = SocksProxy(host: '', port: 0);

  /// 解析 `socks5://user:pass@host:port` / `user:pass@host:port` / `host:port`。
  factory SocksProxy.parse(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return none;
    s = s.replaceFirst(RegExp(r'^socks5h?://', caseSensitive: false), '');
    var user = '';
    var pass = '';
    final at = s.lastIndexOf('@');
    if (at > 0) {
      final auth = s.substring(0, at);
      s = s.substring(at + 1);
      final colon = auth.indexOf(':');
      if (colon > 0) {
        user = Uri.decodeComponent(auth.substring(0, colon));
        pass = Uri.decodeComponent(auth.substring(colon + 1));
      } else {
        user = Uri.decodeComponent(auth);
      }
    }
    s = s.replaceAll(RegExp(r'/+$'), '');
    final colon = s.lastIndexOf(':');
    if (colon <= 0) {
      return SocksProxy(host: s.trim(), port: 1080, username: user, password: pass);
    }
    final host = s.substring(0, colon).trim();
    final port = int.tryParse(s.substring(colon + 1).trim()) ?? 0;
    return SocksProxy(host: host, port: port, username: user, password: pass);
  }

  String get label => isConfigured ? '$host:$port' : '未配置';

  /// `host:port`（不含凭据，可安全展示 / 打日志）。
  String get endpoint => '$host:$port';

  Map<String, dynamic> toJson() =>
      {'host': host, 'port': port, 'username': username, 'password': password};

  static SocksProxy fromJson(Map<String, dynamic>? j) {
    if (j == null) return none;
    return SocksProxy(
      host: '${j['host'] ?? ''}'.trim(),
      port: int.tryParse('${j['port'] ?? 0}') ?? 0,
      username: '${j['username'] ?? ''}',
      password: '${j['password'] ?? ''}',
    );
  }

  /// 换了代理想重连时用：同一个代理只比 endpoint（凭据改了也算换了）。
  @override
  bool operator ==(Object other) =>
      other is SocksProxy &&
      other.host == host &&
      other.port == port &&
      other.username == username &&
      other.password == password;

  @override
  int get hashCode => Object.hash(host, port, username, password);
}

/// SOCKS5 / TLS 通道上的失败（[message] 直接给用户看）。
class SocksException implements Exception {
  const SocksException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 按 [proxy] 建一条到 `targetHost:targetPort` 的连接；
/// [proxy] 未配置时就是普通直连（供校园网内直接用）。
///
/// 返回**裸 TCP**：TLS 由调用方用 [startNoSniTls] / [startTls] 自己加。
Future<Socket> openTunnel(
  SocksProxy proxy,
  String targetHost,
  int targetPort, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (!proxy.isConfigured) {
    try {
      return await Socket.connect(targetHost, targetPort, timeout: timeout);
    } on SocketException catch (e) {
      throw SocksException('连不上 $targetHost：${e.message}');
    } on TimeoutException {
      throw SocksException('连不上 $targetHost：连接超时');
    }
  }
  final socket = await _connectProxy(proxy, timeout);
  final reader = _SocketReader(socket);
  try {
    // 有账号就先提用户名密码（0x02），没有就只提无认证（0x00）
    final methods = proxy.hasAuth ? const <int>[0x02, 0x00] : const <int>[0x00];
    socket.add(<int>[0x05, methods.length, ...methods]);
    await socket.flush();
    final greeting = await reader.readExactly(2, timeout);
    if (greeting[0] != 0x05) throw const SocksException('代理不是 SOCKS5（版本号不对）');
    final method = greeting[1];
    if (method == 0x02) {
      final u = utf8.encode(proxy.username);
      final p = utf8.encode(proxy.password);
      if (u.length > 255 || p.length > 255) throw const SocksException('代理账号密码过长');
      socket.add(<int>[0x01, u.length, ...u, p.length, ...p]);
      await socket.flush();
      final auth = await reader.readExactly(2, timeout);
      if (auth[1] != 0x00) throw const SocksException('SOCKS5 账号或密码被拒绝');
    } else if (method != 0x00) {
      throw const SocksException('代理不接受无认证 / 用户名密码认证方式');
    }
    final hostBytes = utf8.encode(targetHost);
    if (hostBytes.length > 255) throw const SocksException('目标域名过长');
    socket.add(<int>[
      0x05, 0x01, 0x00, 0x03, hostBytes.length, ...hostBytes,
      (targetPort >> 8) & 0xff, targetPort & 0xff,
    ]);
    await socket.flush();
    final head = await reader.readExactly(4, timeout);
    if (head[1] != 0x00) {
      throw SocksException('代理拒绝连接 $targetHost（SOCKS 错误码 ${head[1]}）');
    }
    switch (head[3]) {
      case 0x01:
        await reader.readExactly(4 + 2, timeout);
      case 0x03:
        final n = (await reader.readExactly(1, timeout))[0];
        await reader.readExactly(n + 2, timeout);
      case 0x04:
        await reader.readExactly(16 + 2, timeout);
      default:
        throw SocksException('代理回执地址类型 ${head[3]} 不认识');
    }
    reader.handOff();
    return socket;
  } catch (e) {
    reader.stop();
    socket.destroy();
    if (e is SocksException) rethrow;
    if (e is TimeoutException) throw SocksException('SOCKS5 代理 ${proxy.endpoint} 握手超时');
    throw SocksException('SOCKS5 握手失败：$e');
  }
}

/// 在已连好的 socket 上开 TLS，**不带 SNI**。
///
/// 学校教务的 Tengine 对 Dart/BoringSSL 默认 ClientHello（带 X25519MLKEM768 这类后量子
/// 密钥交换组、带 SNI）会直接 reset；Python 标准库、Windows curl(schannel) 同样被 reset。
/// 去掉 SNI（传 IP 字面量）后服务端回到常规处理路径，握手正常（2026-11 实测）。
/// 代价：主机名不再自动校验，由调用方用 [verifyHost] 按证书补一道。
Future<SecureSocket> startNoSniTls(
  Socket socket, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  // ⚠️ 这里必须传 **InternetAddress**，不能传字符串 IP：
  // SecureSocket.secure 只在 host 是 InternetAddress 时才完全不发 SNI；
  // 传 '10.0.0.1' 这类字符串仍会当成主机名发 SNI，服务端照样 reset（实测）。
  final noSniHost = InternetAddress('10.0.0.1');
  try {
    return await SecureSocket.secure(
      socket,
      host: noSniHost,
      onBadCertificate: (_) => true,
    ).timeout(timeout);
  } on TimeoutException {
    socket.destroy();
    throw const SocksException('TLS 握手超时（校园代理链路很慢，或学校站点在维护）');
  } on HandshakeException catch (e) {
    socket.destroy();
    throw SocksException('TLS 握手失败：${e.message}');
  }
}

/// 带 SNI 的常规 TLS（公网站点 / 学校已换证书时用）。
Future<SecureSocket> startTls(Socket socket, {required String host, bool allowBad = false}) =>
    SecureSocket.secure(socket, host: host, onBadCertificate: (_) => allowBad);

/// 校验证书是否属于 [expected]（CN 或 SAN 里出现该域名，或其父域通配）。
///
/// [startNoSniTls] 走的是「不校验主机名」路径，这一步是它的补丁：代理后面若不是学校
/// （或证书被换成别的），就拒绝继续，避免把教务密码发给不明服务端。
bool verifyHost(X509Certificate cert, String expected) {
  final want = expected.trim().toLowerCase();
  if (want.isEmpty) return true;
  String decodeOrEmpty(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true).toLowerCase();
    } catch (_) {
      return '';
    }
  }

  final hay = <String>[cert.subject.toLowerCase()];
  // pem 是 base64：解回 DER 才能看到 SAN 里的 dNSName 明文
  try {
    final pem = cert.pem;
    final body = pem
        .replaceAll(RegExp(r'-----[^-]+-----'), '')
        .replaceAll(RegExp(r'\s+'), '');
    hay.add(decodeOrEmpty(base64Decode(body)));
  } catch (_) {}

  for (final text in hay) {
    if (text.isEmpty) continue;
    if (text.contains(want)) return true;
    final dot = want.indexOf('.');
    // 父域通配（*.sit.edu.cn）与同域子证书
    if (dot > 0 && text.contains(want.substring(dot))) return true;
  }
  return false;
}

Future<Socket> _connectProxy(SocksProxy proxy, Duration timeout) async {
  try {
    return await Socket.connect(proxy.host, proxy.port, timeout: timeout);
  } on SocketException catch (e) {
    throw SocksException('连不上 SOCKS5 代理 ${proxy.endpoint}：${e.message}');
  } on TimeoutException {
    throw SocksException('连不上 SOCKS5 代理 ${proxy.endpoint}：连接超时');
  }
}

/// 只读前 N 字节、其余原样交还的单订阅读取器：SOCKS 握手要在**同一个** Socket 上
/// 精确读定长回执，读完不能把后续数据吞掉——紧接着就是 TLS 握手，少一个字节都握不上。
class _SocketReader {
  _SocketReader(this._socket) {
    _sub = _socket.listen(
      (data) {
        _buffer.addAll(data);
        _wake?.complete();
        _wake = null;
      },
      onError: (Object e, StackTrace st) {
        _error = e;
        _wake?.completeError(e, st);
        _wake = null;
      },
      onDone: () {
        _done = true;
        _wake?.complete();
        _wake = null;
      },
    );
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _sub;
  final List<int> _buffer = <int>[];
  Completer<void>? _wake;
  Object? _error;
  bool _done = false;

  Future<Uint8List> readExactly(int n, Duration timeout) async {
    while (_buffer.length < n) {
      if (_error != null) throw SocksException('代理连接中断：$_error');
      if (_done) throw const SocksException('代理提前关闭了连接');
      final c = Completer<void>();
      _wake = c;
      try {
        await c.future.timeout(timeout);
      } on TimeoutException {
        throw const SocksException('等待代理应答超时');
      } finally {
        if (identical(_wake, c)) _wake = null;
      }
    }
    final out = Uint8List.fromList(_buffer.sublist(0, n));
    _buffer.removeRange(0, n);
    return out;
  }

  /// 把 socket 交给 TLS：**只是暂停**订阅。
  ///
  /// 不能 cancel——Dart 在最后一个订阅被取消时会顺手 shutdown(receive)，
  /// 之后的 TLS 握手就再也读不到服务端应答（表现为 Connection terminated during handshake）。
  /// 官方文档对 SecureSocket.secure 的建议也是「先 pause 再交出去」。
  void handOff() {
    if (_handedOff) return;
    _handedOff = true;
    _sub.pause();
  }

  /// 出错时彻底放弃这条连接（socket 随后会被 destroy）。
  void stop() {
    if (_handedOff) return;
    _handedOff = true;
    unawaited(_sub.cancel());
  }

  bool _handedOff = false;
}