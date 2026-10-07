import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import 'direct/school.dart';

/// 工具页与子页共享的缓存数值（用于宫格卡面速览）。
class ToolCache {
  static Map<String, dynamic>? score;
  static Map<String, dynamic>? electricity;
}

/// 数据来源模式：
/// - server：服务器账号登录远程服务器，由服务器代连校园内网（原模式）
/// - direct：用校园凭据直接访问学校系统，不走服务器，需设备在校园网 / 校内 VPN 内
enum AppMode { server, direct }

/// 全局登录态与设置（内存态 + SharedPreferences 持久化）。
/// 服务器模式登录 = 服务器账号换 30 天 JWT；直连模式登录 = 本机保存的校园凭据。
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState I = AppState._();

  static const localUrl = 'http://127.0.0.1:8000';

  bool loaded = false;
  bool demo = false;
  AppMode mode = AppMode.server;

  String serverUrl = ''; // 空 = 尚未配置，引导去「连接设置」填写

  String? token; // JWT，持久化（30 天有效，服务重启不失效）
  String? username;
  String? password; // 仅勾选「记住密码」时持久化
  bool remember = true;

  /// 外观模式：跟随系统 / 浅色 / 深色（液态玻璃主题）。
  ThemeMode themeMode = ThemeMode.system;

  /// 直连模式：学校档案（可多个）+ 当前学校 + 校园凭据。
  List<SchoolProfile> schools = [];
  SchoolProfile school = SchoolProfile.sit();
  CampusCreds creds = CampusCreds();

  /// /status 返回缓存（configured / has_pay_password / auto_captcha 等）。
  Map<String, dynamic>? statusInfo;

  /// /score 返回的 student 节点缓存（院系/专业/班级等）。
  Map<String, dynamic>? studentInfo;

  bool get direct => mode == AppMode.direct;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    serverUrl = sp.getString('server_url') ?? '';
    demo = kDebugMode && (sp.getBool('demo') ?? false); // 演示模式仅 debug 构建可用
    remember = sp.getBool('remember') ?? true;
    token = sp.getString('token');
    themeMode = switch (sp.getString('theme_mode')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    mode = sp.getString('app_mode') == 'direct' ? AppMode.direct : AppMode.server;
    schools = SchoolProfile.decodeList(sp.getString('direct_schools'));
    if (schools.isEmpty) schools = [SchoolProfile.sit()];
    final active = sp.getString('direct_school') ?? '';
    school = schools.firstWhere((s) => s.name == active, orElse: () => schools.first);
    creds = CampusCreds.fromJson(_decodeObj(sp.getString('direct_creds')));
    if (remember) {
      username = sp.getString('username');
      password = sp.getString('password');
    }
    loaded = true;
    // 主题等偏好可能在首帧后才异步加载完成，通知根组件按持久化偏好重建
    notifyListeners();
  }

  static Map<String, dynamic>? _decodeObj(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      return j is Map ? j.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('demo', demo);
    await sp.setString('server_url', serverUrl);
    await sp.setBool('remember', remember);
    await sp.setString('theme_mode',
        switch (themeMode) { ThemeMode.light => 'light', ThemeMode.dark => 'dark', _ => 'system' });
    await sp.setString('app_mode', direct ? 'direct' : 'server');
    await sp.setString('direct_schools', SchoolProfile.encodeList(schools));
    await sp.setString('direct_school', school.name);
    await sp.setString('direct_creds', jsonEncode(creds.toJson()));
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

  /// 直连模式的学校 / 凭据改动落盘（不改登录 token）。
  Future<void> persistDirect() => _persist();

  Future<void> setMode(AppMode m) async {
    mode = m;
    await _persist();
    notifyListeners();
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

  /// 服务器地址（服务器模式）：自动补协议、去尾部斜杠。
  static String normalizeServer(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    final hasScheme = s.startsWith('http://') || s.startsWith('https://');
    final host = s.split('://').last.split('/').first.split(':').first;
    final isIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
    final isLocal = host == 'localhost' || host == '127.0.0.1';
    if (!hasScheme) s = (isIp || isLocal) ? 'http://$s' : 'https://$s';
    return s.replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> setServer(String url) async {
    serverUrl = normalizeServer(url);
    await _persist();
    notifyListeners();
  }

  Future<void> setRemember(bool v) async {
    remember = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await _persist();
    notifyListeners();
  }

  /// 直连模式：切换当前学校（保留各校凭据不区分，切换即重新登录）。
  Future<void> setSchool(SchoolProfile s) async {
    school = s;
    await _persist();
    notifyListeners();
  }

  /// 新增 / 更新学校档案（按名称或域名匹配覆盖）。
  Future<void> upsertSchool(SchoolProfile s) async {
    final i = schools.indexWhere((e) => e.name == s.name);
    if (i >= 0) {
      schools[i] = s;
    } else {
      schools.add(s);
    }
    if (school.name == s.name) school = s;
    await _persist();
    notifyListeners();
  }

  Future<void> removeSchool(String name) async {
    schools.removeWhere((e) => e.name == name);
    if (schools.isEmpty) schools = [SchoolProfile.sit()];
    if (school.name == name) school = schools.first;
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

  /// 直连模式退出：清校园密码（保留学号/寝室/姓名便于再次登录）。
  Future<void> clearDirectSession() async {
    creds.password = '';
    creds.payPassword = '';
    statusInfo = null;
    studentInfo = null;
    await _persist();
    notifyListeners();
  }

  bool get loggedIn => demo || (direct ? creds.hasLogin : token != null);
  bool get hasCreds => (username ?? '').isNotEmpty && (password ?? '').isNotEmpty;

  /// 按日期推算当前学年学期：xqm 3=第一学期，12=第二学期（正方约定）。
  static (String, String) inferSemester(DateTime now) {
    final y = now.year, m = now.month;
    if (m >= 9) return ('$y', '3');
    if (m >= 3 && m <= 8) return ('${y - 1}', '12');
    return ('${y - 1}', '3');
  }
}
