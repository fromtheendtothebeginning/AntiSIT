import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 工具页与子页共享的缓存数值（用于宫格卡面速览）。
class ToolCache {
  static Map<String, dynamic>? score;
  static Map<String, dynamic>? electricity;
}

/// 全局登录态与设置（内存态 + SharedPreferences 持久化）。
/// 登录 = anticraft 账号换 30 天 JWT；校园凭据在网站配置，App 不经手校园密码。
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState I = AppState._();

  static const prodUrl = 'https://anticraft.top';
  static const localUrl = 'http://127.0.0.1:8000';

  bool loaded = false;
  bool demo = false;

  String serverUrl = prodUrl;

  String? token; // JWT，持久化（30 天有效，服务重启不失效）
  String? username;
  String? password; // 仅勾选「记住密码」时持久化
  bool remember = true;

  /// /status 返回缓存（configured / has_pay_password / auto_captcha 等）。
  Map<String, dynamic>? statusInfo;

  /// /score 返回的 student 节点缓存（院系/专业/班级等）。
  Map<String, dynamic>? studentInfo;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    serverUrl = sp.getString('server_url') ?? prodUrl;
    demo = sp.getBool('demo') ?? false;
    remember = sp.getBool('remember') ?? true;
    token = sp.getString('token');
    if (remember) {
      username = sp.getString('username');
      password = sp.getString('password');
    }
    loaded = true;
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('demo', demo);
    await sp.setString('server_url', serverUrl);
    await sp.setBool('remember', remember);
    final token = this.token;
    if (token != null) {
      await sp.setString('token', token);
    } else {
      await sp.remove('token');
    }
    if (remember && username != null && password != null) {
      await sp.setString('username', username!);
      await sp.setString('password', password!);
    } else {
      await sp.remove('username');
      await sp.remove('password');
    }
  }

  /// 登录成功后写入会话；[remember] 为 false 时密码只留在内存。
  Future<void> saveLogin({
    required String token,
    required String username,
    String? password,
  }) async {
    this.token = token;
    this.username = username;
    if (password != null && password.isNotEmpty) this.password = password;
    demo = false;
    await _persist();
    notifyListeners();
  }

  Future<void> setDemo(bool v) async {
    demo = v;
    if (v) token = null;
    await _persist();
    notifyListeners();
  }

  Future<void> setServer(String url) async {
    serverUrl = url;
    await _persist();
    notifyListeners();
  }

  Future<void> setRemember(bool v) async {
    remember = v;
    await _persist();
    notifyListeners();
  }

  /// 清除会话；[keepCreds] 为 true 时保留记住的账号密码。
  Future<void> clearSession({bool keepCreds = true}) async {
    token = null;
    statusInfo = null;
    studentInfo = null;
    if (!keepCreds) {
      username = null;
      password = null;
    }
    await _persist();
    notifyListeners();
  }

  bool get loggedIn => demo || token != null;
  bool get hasCreds => (username ?? '').isNotEmpty && (password ?? '').isNotEmpty;

  /// 按日期推算当前学年学期：xqm 3=第一学期，12=第二学期（正方约定）。
  static (String, String) inferSemester(DateTime now) {
    final y = now.year, m = now.month;
    if (m >= 9) return ('$y', '3');
    if (m >= 3 && m <= 8) return ('${y - 1}', '12');
    return ('${y - 1}', '3');
  }
}
