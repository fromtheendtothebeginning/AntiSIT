import 'package:campus_core/campus_core.dart';

/// 评教用的教务会话：直接复用 App 已有的教务登录态（[ApiClient.jwxtWebSession]），不再自己登录。
/// 直连模式是本机已登录的 Cookie，服务器模式是服务器代连的 Cookie + 它给的教务域名。
class EvaluateSession {
  EvaluateSession({this.fallbackBase = ''});

  /// 学校档案里的教务地址（服务器没给域名时用它）。
  final String fallbackBase;

  /// 主机 → （cookie 名 → 值）。
  final Map<String, Map<String, String>> _jar = {};

  /// 服务器返回的教务根地址；空 = 用 [fallbackBase]。
  String serverBase = '';

  bool get hasCookies => _jar.values.any((m) => m.isNotEmpty);

  /// 教务根地址（不带尾斜杠）。
  String get base {
    final raw = serverBase.trim().isNotEmpty ? serverBase.trim() : fallbackBase.trim();
    return raw.replaceAll(RegExp(r'/+$'), '');
  }

  String cookieHeader(String host) {
    final parts = <String>[];
    _jar.forEach((domain, cookies) {
      if (host == domain || host.endsWith('.$domain')) {
        cookies.forEach((k, v) => parts.add('$k=$v'));
      }
    });
    return parts.join('; ');
  }

  /// 把 [ApiClient.jwxtWebSession] 给的会话灌进来（Cookie 归属到教务域名）。
  void adopt(JwxtWebSession session) {
    _jar.clear();
    serverBase = session.base;
    final host = Uri.tryParse(base)?.host ?? '';
    if (host.isEmpty || session.cookies.isEmpty) return;
    _jar[host] = Map<String, String>.from(session.cookies);
  }

  /// 吸收响应里的 Set-Cookie（教务会在部分接口上续期会话）。
  void absorbCookies(String host, List<String> setCookies) {
    if (setCookies.isEmpty) return;
    for (final line in setCookies) {
      final seg = line.split(';');
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
      (_jar[domain] ??= <String, String>{})[name] = value;
    }
  }
}