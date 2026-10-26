import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import 'direct/school.dart';
import 'json_num.dart';
import 'secure_store.dart';

/// 二课分数快照（/score 的 data 节点）：宫格副标题与「学籍信息」的常用字段
/// 强类型访问；详情页要挖别的字段走 [raw]。
class ScoreSnapshot {
  const ScoreSnapshot._(this.raw);

  factory ScoreSnapshot.fromJson(Map<String, dynamic> j) => ScoreSnapshot._(j);

  final Map<String, dynamic> raw;

  /// 已得分 / 达标分（缺字段按 0，副标题不至于显示 null）。
  /// 学工接口的 zxs/sjxf 是字符串（如 "8.0"），只认 num 会让卡面显示 0/0。
  num get credit => asNum(raw['credit']) ?? 0;
  num get total => asNum(raw['total']) ?? 0;

  /// 学籍信息节点（院系 / 专业 / 班级），「我的 → 学籍信息」用。
  Map<String, dynamic>? get student =>
      raw['student'] is Map<String, dynamic> ? raw['student'] as Map<String, dynamic> : null;
}

/// 宿舍电费快照（/electricity/query 的 data 节点）。
class ElectricitySnapshot {
  const ElectricitySnapshot._(this.raw);

  factory ElectricitySnapshot.fromJson(Map<String, dynamic> j) => ElectricitySnapshot._(j);

  final Map<String, dynamic> raw;

  /// 当前余额（元）。
  num get balance => asNum(raw['balance']) ?? 0;
}

/// 工具页与子页共享的缓存数值（用于宫格卡面速览）。
class ToolCache {
  static ScoreSnapshot? score;
  static ElectricitySnapshot? electricity;

  /// data 节点缺失 / 类型不对时给 null，把判空集中在这一处。
  static ScoreSnapshot? scoreOf(Object? data) =>
      data is Map<String, dynamic> ? ScoreSnapshot.fromJson(data) : null;

  static ElectricitySnapshot? electricityOf(Object? data) =>
      data is Map<String, dynamic> ? ElectricitySnapshot.fromJson(data) : null;
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

  /// 课表：是否把「已上完」的课淡化（关掉则与未上完的课一样显示正常彩色）。
  bool dimCompleted = true;

  /// 界面是否实时跟着滑块切换：开（默认）= 拖动时下方界面跟着滑块连续滑动、
  /// 并在拖过一半时就换（主界面底栏切页 / 连接设置都算）；
  /// 关 = 松手落位后才切换（旧行为，省一点重绘）。开关在「我的 → 设置 → 外观」里。
  bool followSlider = true;

  /// 预测式返回动画开关：开（默认）= 系统返回手势跟手预览、松手可反悔；
  /// 关 = 手势期间画面不动，松手按普通返回（淡入淡出）。开关在「我的 → 设置 → 外观」里。
  bool predictiveBack = true;

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
    final secure = SecureStore.I;
    serverUrl = sp.getString('server_url') ?? '';
    demo = kDebugMode && (sp.getBool('demo') ?? false); // 演示模式仅 debug 构建可用
    remember = sp.getBool('remember') ?? true;
    // 敏感值走加密存储；早期版本留在明文 SharedPreferences 里的旧值一次性迁入
    token = await _migrate(secure, sp, 'token');
    themeMode = switch (sp.getString('theme_mode')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    dimCompleted = sp.getBool('dim_completed') ?? true;
    followSlider = sp.getBool('follow_slider') ?? true;
    predictiveBack = sp.getBool('predictive_back') ?? true;
    mode = sp.getString('app_mode') == 'direct' ? AppMode.direct : AppMode.server;
    schools = SchoolProfile.decodeList(sp.getString('direct_schools'));
    if (schools.isEmpty) schools = [SchoolProfile.sit()];
    final active = sp.getString('direct_school') ?? '';
    school = schools.firstWhere((s) => s.name == active, orElse: () => schools.first);
    creds = CampusCreds.fromJson(_decodeObj(await _migrate(secure, sp, 'direct_creds')));
    if (remember) {
      username = await _migrate(secure, sp, 'username');
      password = await _migrate(secure, sp, 'password');
    }
    loaded = true;
    // 主题等偏好可能在首帧后才异步加载完成，通知根组件按持久化偏好重建
    notifyListeners();
  }

  /// 加密存储优先；它没有而明文 SharedPreferences 里有（旧版本写入的）→
  /// 采用明文值、写入加密存储、删掉明文。
  static Future<String?> _migrate(
      SecureStore secure, SharedPreferences sp, String key) async {
    final v = await secure.read(key);
    if (v != null && v.isNotEmpty) return v;
    final legacy = sp.getString(key);
    if (legacy == null || legacy.isEmpty) return null;
    await secure.write(key, legacy);
    await sp.remove(key);
    return legacy;
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
    final secure = SecureStore.I;
    await sp.setBool('demo', demo);
    await sp.setString('server_url', serverUrl);
    await sp.setBool('remember', remember);
    await sp.setString('theme_mode',
        switch (themeMode) { ThemeMode.light => 'light', ThemeMode.dark => 'dark', _ => 'system' });
    await sp.setBool('dim_completed', dimCompleted);
    await sp.setBool('follow_slider', followSlider);
    await sp.setBool('predictive_back', predictiveBack);
    await sp.setString('app_mode', direct ? 'direct' : 'server');
    await sp.setString('direct_schools', SchoolProfile.encodeList(schools));
    await sp.setString('direct_school', school.name);
    await _putSecure(secure, sp, 'direct_creds', jsonEncode(creds.toJson()));
    await _putSecure(secure, sp, 'token', token);
    if (remember && username != null && password != null) {
      await _putSecure(secure, sp, 'username', username!);
      await _putSecure(secure, sp, 'password', password!);
    } else {
      await _putSecure(secure, sp, 'username', null);
      await _putSecure(secure, sp, 'password', null);
    }
  }

  /// 敏感值写加密存储；顺带清掉早期版本可能留在明文里的同名 key。
  /// 值为 null / 空表示删除。
  static Future<void> _putSecure(
      SecureStore secure, SharedPreferences sp, String key, String? value) async {
    if (value != null && value.isNotEmpty) {
      await secure.write(key, value);
    } else {
      await secure.remove(key);
    }
    await sp.remove(key);
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

  /// 「外观」滑块拖动中的实时深浅（0 = 全浅色、1 = 全深色，见 `appearanceDarkness`）；
  /// null = 没在拖，按 [themeMode] 走。**不持久化**：它只是拖动时的预览，
  /// 静止时其值与该档对应的配色一致，所以松手不会跳。
  double? appearancePreviewDark;

  /// 拖动「外观」滑块时更新预览。整站配色是全局的（`SemColors`），每帧重建界面太贵，
  /// 所以**量化到 5% 一步**再通知：视觉上仍是连续渐变，重建次数少一个数量级。
  void setAppearancePreview(double? v) {
    if (v == null) {
      if (appearancePreviewDark == null) return;
      appearancePreviewDark = null;
      notifyListeners();
      return;
    }
    final q = (v * 20).round() / 20; // 0.05 一步
    if (appearancePreviewDark == q) return;
    appearancePreviewDark = q;
    notifyListeners();
  }

  /// 课表：是否淡化「已上完」的课（关掉则显示正常彩色）。
  Future<void> setDimCompleted(bool v) async {
    dimCompleted = v;
    await _persist();
    notifyListeners();
  }

  /// 界面是否实时跟着滑块切换（见 [followSlider]）。
  Future<void> setFollowSlider(bool v) async {
    followSlider = v;
    await _persist();
    notifyListeners();
  }

  /// 预测式返回动画开关（见 [predictiveBack]）。
  Future<void> setPredictiveBack(bool v) async {
    predictiveBack = v;
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
