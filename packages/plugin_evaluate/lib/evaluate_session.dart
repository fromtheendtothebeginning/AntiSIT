import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_core/campus_core.dart';

/// 教务评教会话：Cookie 罐 + 登录中间态（csrftoken / 加密后的密码）。
///
/// Cookie 存在 [SecureStore]（Android Keystore / iOS Keychain）——
/// 会话在有效期内等价于登录态（能提交评教），不能落明文。
class EvaluateSession {
  EvaluateSession({this.persistKey = _defaultKey});

  static const String _defaultKey = 'evaluate_jwxt_cookies_v1';

  final String persistKey;

  /// 主机 → (cookie 名 → 值)。
  final Map<String, Map<String, String>> _jar = {};

  /// 登录中间态（只在一次登录流程内有效，不持久化）。
  String? csrf;
  String? studentId;
  String? encPassword;

  bool get hasCookies => _jar.values.any((m) => m.isNotEmpty);
  int get cookieCount => _jar.values.fold(0, (a, m) => a + m.length);

  String cookieHeader(String host) {
    final parts = <String>[];
    _jar.forEach((domain, cookies) {
      if (host == domain || host.endsWith('.' + domain)) {
        cookies.forEach((k, v) => parts.add(k + '=' + v));
      }
    });
    return parts.join('; ');
  }

  /// 吸收响应里的 Set-Cookie（按 Domain 属性归罐）。
  void absorbCookies(String host, List<String> setCookies) {
    if (setCookies.isEmpty) return;
    var changed = false;
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
      changed = true;
    }
    if (changed) unawaitedPersist();
  }

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = await SecureStore.I.read(persistKey);
      await sp.remove(persistKey); // 清掉旧版本可能留下的明文
      if (raw == null || raw.isEmpty) return;
      final obj = jsonDecode(raw);
      if (obj is Map) {
        obj.forEach((host, cookies) {
          if (cookies is Map) {
            _jar[host.toString()] = {
              for (final e in cookies.entries) e.key.toString(): e.value.toString(),
            };
          }
        });
      }
    } catch (_) {}
  }

  Future<void> persist() => SecureStore.I.write(persistKey, jsonEncode(_jar));

  /// 吸收 Cookie 后异步落盘（不阻塞请求）。
  void unawaitedPersist() {
    unawaited(persist().catchError((Object _) {}));
  }

  Future<void> clear() async {
    _jar.clear();
    csrf = null;
    studentId = null;
    encPassword = null;
    await SecureStore.I.remove(persistKey);
  }

  /// 给测试 / 调试看：不含值，只报有哪些主机。
  List<String> get hosts => _jar.keys.toList();
}