import 'dart:convert';

import 'package:campus_core/campus_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 评教的持久化设置：校园代理地址 + 账号（密码跟随 App 的直连凭据，不单独存）。
///
/// **代理凭据不进 git、不编译进 App**：只存在本机（[SecureStore]，Android Keystore /
/// iOS Keychain）。首次可以用构建参数注入：
/// `flutter build apk --dart-define=ANTISIT_EVAL_PROXY=host:port`
/// `--dart-define=ANTISIT_EVAL_USER=xxx --dart-define=ANTISIT_EVAL_PASS=xxx`
class EvaluateSettings {
  static final EvaluateSettings I = EvaluateSettings._();
  EvaluateSettings._();

  static const String _prefsKey = 'evaluate_settings_v1';
  static const String _secretKey = 'evaluate_proxy_secret_v1';

  /// 校园代理（SOCKS5）。未配置时直连校园网。
  SocksProxy proxy = SocksProxy.none;

  /// 评教用的学号；空 = 用 App 直连凭据里的学号。
  String studentId = '';

  /// 评教用的教务密码；空 = 用 App 直连凭据里的统一身份认证密码。
  String password = '';

  bool loaded = false;

  /// App 直连凭据（学号 / 统一身份认证密码）——评教默认复用它。
  String get effectiveStudentId =>
      studentId.trim().isNotEmpty ? studentId.trim() : AppState.I.creds.studentId.trim();

  String get effectivePassword =>
      password.isNotEmpty ? password : AppState.I.creds.password;

  bool get hasCredential =>
      effectiveStudentId.isNotEmpty && effectivePassword.isNotEmpty;

  bool get ready => proxy.isConfigured && hasCredential;

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw);
        if (j is Map) {
          studentId = (j['student_id'] ?? '').toString();
          final p = j['proxy'];
          if (p is Map) proxy = SocksProxy.fromJson(p.cast<String, dynamic>());
        }
      }
      final secret = await SecureStore.I.read(_secretKey);
      if (secret != null && secret.isNotEmpty) {
        final j = jsonDecode(secret);
        if (j is Map) {
          final p = j['proxy'];
          if (p is Map) {
            final parsed = SocksProxy.fromJson(p.cast<String, dynamic>());
            proxy = SocksProxy(
              host: parsed.host,
              port: parsed.port,
              username: parsed.username,
              password: parsed.password,
            );
          }
          password = (j['password'] ?? '').toString();
        }
      }
    } catch (_) {}
    _applyCompileDefaults();
    loaded = true;
  }

  /// 构建期注入的默认值（不进仓库；只有显式 --dart-define 才有值）。
  void _applyCompileDefaults() {
    const endpoint = String.fromEnvironment('ANTISIT_EVAL_PROXY');
    const user = String.fromEnvironment('ANTISIT_EVAL_USER');
    const pass = String.fromEnvironment('ANTISIT_EVAL_PASS');
    if (endpoint.isEmpty) return;
    // 已经在本机配过就不覆盖（用户手填优先）
    if (proxy.isConfigured) return;
    proxy = SocksProxy(
      host: SocksProxy.parse(endpoint).host,
      port: SocksProxy.parse(endpoint).port,
      username: user,
      password: pass,
    );
  }

  Future<void> save({SocksProxy? proxy, String? studentId, String? password}) async {
    if (proxy != null) this.proxy = proxy;
    if (studentId != null) this.studentId = studentId.trim();
    if (password != null) this.password = password;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _prefsKey,
      jsonEncode({
        'student_id': this.studentId,
        'proxy': {'host': this.proxy.host, 'port': this.proxy.port},
      }),
    );
    await SecureStore.I.write(
      _secretKey,
      jsonEncode({
        'password': this.password,
        'proxy': this.proxy.toJson(),
      }),
    );
  }

  /// 设置页展示用：不暴露密码，只说明「用 App 凭据 / 单独填写」。
  String get credentialSource =>
      studentId.trim().isNotEmpty ? '单独填写（' + maskStudentId(studentId) + '）' : '复用 App 的直连凭据';
}