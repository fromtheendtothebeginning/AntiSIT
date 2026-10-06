import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../api_error.dart';
import '../app_state.dart';
import 'activities_util.dart';
import 'epay.dart';
import 'jwxt.dart';
import 'school.dart';
import 'xg.dart';

/// 探测结果（连接设置页「测试连接」逐项展示）。
typedef ProbeResult = ({String name, bool ok, String detail});

/// 验证码输入回调：UI 层注入（返回 null = 用户取消；refresh 用于「换一张」）。
/// [error] 非空表示上一次提交失败，弹窗据此提示原因（如「验证码错误」）。
typedef CaptchaPrompt = Future<String?> Function(
  Uint8List image,
  String hint,
  Future<Uint8List> Function() refresh, {
  String? error,
});

/// 直连模式总控：App 用校园凭据直接访问学校系统（教务 / 学工 / 校付宝），
/// 不经 anticraft 服务器——因此需要设备本身在校园网（或校内 VPN）内。
/// 验证码由用户手动输入（服务器模式的 AI 识码不适用直连）。
class CampusDirect {
  static final CampusDirect I = CampusDirect._();
  CampusDirect._();

  /// 验证码输入回调：由 UI 层注入（返回 null = 用户取消）。
  Future<String?> Function(Uint8List image, String hint, Future<Uint8List> Function() refresh,
      {String? error})? captchaPrompt;

  JwxtClient? _jwxt;
  XgClient? _xg;
  EpayClient? _epay;
  String _schoolKey = '';
  String _realNameCache = '';

  /// 登录单飞：主页四个 Tab 同时常驻，启动时会并发查询（课表 / 二课 / 电费 / 学籍），
  /// 若各自独立走一遍登录流程，验证码弹窗就会叠着弹好几次。
  /// 同一系统的登录只跑一次，并发调用者共享同一个 Future。
  Future<void>? _xgLogin;
  Future<void>? _jwxtLogin;

  static const String _histKey = 'direct_electricity_history';

  // ==================== 会话与客户端 ====================

  void _syncClients() {
    final s = AppState.I.school;
    final key = [s.name, s.authBase, s.jwxtBase, s.xgBase, s.ecardBase, s.dektAesKey].join('|');
    if (key == _schoolKey) return;
    _jwxt?.dispose();
    _xg?.dispose();
    _epay?.dispose();
    _jwxt = null;
    _xg = null;
    _epay = null;
    _schoolKey = key;
    _realNameCache = '';
    _xgLogin = null; // 换学校后旧客户端的登录流程作废
    _jwxtLogin = null;
  }

  JwxtClient get _jwxtClient {
    _syncClients();
    return _jwxt ??= JwxtClient(AppState.I.school.jwxtBase, aesKey: AppState.I.school.dektAesKey);
  }

  XgClient get _xgClient {
    _syncClients();
    return _xg ??=
        XgClient(authBase: AppState.I.school.authBase, xgBase: AppState.I.school.xgBase);
  }

  EpayClient get _epayClient {
    _syncClients();
    return _epay ??= EpayClient(AppState.I.school.ecardBase);
  }

  /// 断开直连会话（登录态与 Cookie 一并清掉，下次查询必须重新登录）。
  /// 注意：Cookie 是持久化在 SharedPreferences 里的，只丢客户端对象会让下次查询
  /// 悄悄复用旧会话，所以这里必须清 Cookie。
  Future<void> disconnect() async {
    _jwxt?.clearSession();
    _xg?.clearSession();
    _epay?.clearSession();
    _jwxt?.dispose();
    _xg?.dispose();
    _epay?.dispose();
    _jwxt = null;
    _xg = null;
    _epay = null;
    _realNameCache = '';
    _schoolKey = '';
    _xgLogin = null;
    _jwxtLogin = null;
  }

  /// 凭据/学校改动后调用：保留 Cookie，仅要求重新走登录流程。
  void forgetLoginState() {
    _jwxt?.loggedIn = false;
    _xg?.loggedIn = false;
    _epay = null;
    _realNameCache = '';
    _xgLogin = null;
    _jwxtLogin = null;
  }

  CampusCreds get _cred => AppState.I.creds;

  void _requireCreds() {
    if (!_cred.hasLogin) {
      throw ApiError('请先在「连接设置 → 直连模式」填写学号和统一身份认证密码');
    }
  }

  Future<String?> _askCaptcha(
    Uint8List image,
    String hint,
    Future<Uint8List> Function() refresh, {
    String? error,
  }) async {
    final prompt = captchaPrompt;
    if (prompt == null) throw ApiError('$hint：需要输入验证码，但当前界面无法弹出输入框');
    return prompt(image, hint, refresh, error: error);
  }

  /// 学校系统回文案里含「验证码」→ 只是码输错了，换一张重输；否则（密码/账号错）直接抛出，
  /// 免得拿同一个错误密码连弹三次验证码。
  static bool _isCaptchaError(String msg) => msg.contains('验证码');

  /// 学工 CAS 登录（持久化 Cookie 仍有效时免验证码）。
  Future<void> _ensureXg() {
    final inflight = _xgLogin;
    if (inflight != null) return inflight; // 并发查询复用同一次登录（只弹一次验证码）
    if (_xg != null && _xg!.loggedIn) return Future.value();
    final f = _loginXg();
    _xgLogin = f;
    return f.whenComplete(() {
      if (identical(_xgLogin, f)) _xgLogin = null;
    });
  }

  Future<void> _loginXg() async {
    _requireCreds();
    if (_xg != null && _xg!.loggedIn) return;
    final client = _xgClient;
    String? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      final image = await client.prepareLogin(_cred.studentId, _cred.password);
      if (image == null) return; // 已有会话
      if (image.isEmpty) throw ApiError('统一认证验证码获取失败，请稍后重试');
      final text = await _askCaptcha(image, '统一身份认证验证码', () async {
        final img = await client.prepareLogin(_cred.studentId, _cred.password);
        if (img == null || img.isEmpty) throw ApiError('验证码获取失败，请重试');
        return img;
      }, error: lastError);
      if (text == null || text.trim().isEmpty) throw ApiError('已取消验证码输入');
      try {
        await client.completeLogin(text.trim());
        return;
      } on ApiError catch (e) {
        lastError = e.message;
        if (!_isCaptchaError(lastError)) rethrow;
      }
    }
    throw ApiError('统一认证登录失败：${lastError ?? '请稍后重试'}');
  }

  /// 正方教务登录（持久化 Cookie 仍有效时免验证码）。
  Future<void> _ensureJwxt() {
    final inflight = _jwxtLogin;
    if (inflight != null) return inflight;
    if (_jwxt != null && _jwxt!.loggedIn) return Future.value();
    final f = _loginJwxt();
    _jwxtLogin = f;
    return f.whenComplete(() {
      if (identical(_jwxtLogin, f)) _jwxtLogin = null;
    });
  }

  Future<void> _loginJwxt() async {
    _requireCreds();
    if (_jwxt != null && _jwxt!.loggedIn) return;
    final client = _jwxtClient;
    if (await client.checkSession()) return;
    String? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      final image = await client.prepareLogin(_cred.studentId, _cred.password);
      if (image.isEmpty) throw ApiError('教务验证码获取失败，请稍后重试');
      final text = await _askCaptcha(image, '教务系统验证码', () async {
        final img = await client.prepareLogin(_cred.studentId, _cred.password);
        if (img.isEmpty) throw ApiError('验证码获取失败，请重试');
        return img;
      }, error: lastError);
      if (text == null || text.trim().isEmpty) throw ApiError('已取消验证码输入');
      try {
        await client.completeLogin(text.trim());
        return;
      } on ApiError catch (e) {
        lastError = e.message;
        if (!_isCaptchaError(lastError)) rethrow;
      }
    }
    throw ApiError('教务系统登录失败：${lastError ?? '请稍后重试'}');
  }

  /// 校付宝登录用的真实姓名：优先用填写值，其次查学工补全。
  Future<String> _realName() async {
    final filled = _cred.realName.trim();
    if (filled.isNotEmpty) return filled;
    if (_realNameCache.isNotEmpty) return _realNameCache;
    try {
      await _ensureXg();
      final s = await _xg!.score(_cred.studentId);
      final xm = ((s['student'] as Map?)?['xm'] ?? '').toString().trim();
      if (xm.isNotEmpty) {
        _realNameCache = xm;
        _cred.realName = xm;
        await AppState.I.persistDirect();
        return xm;
      }
    } catch (_) {}
    throw ApiError('校付宝登录需要真实姓名：请在「连接设置 → 直连模式」填写姓名'
        '（或在校园网下先查询第二课堂分数自动补全）');
  }

  // ==================== 状态 / 断开 ====================

  Future<Map<String, dynamic>> status() async {
    final cred = _cred;
    return {
      'ok': true,
      'direct': true,
      'school': AppState.I.school.name,
      'configured': cred.hasLogin,
      'student_id_masked': cred.studentId.isEmpty ? null : maskStudentId(cred.studentId),
      'has_pay_password': cred.hasPay,
      'has_dorm': cred.hasDorm,
      'auto_captcha': false, // 直连模式为手动输入验证码
      'session': {'connected': true, 'status': 'direct', 'error': null},
      'cas_ready': _xg?.loggedIn ?? false,
      'jwxt_ready': _jwxt?.loggedIn ?? false,
    };
  }

  // ==================== 学工：二课分 / 活动 ====================

  Future<Map<String, dynamic>> score() async {
    await _ensureXg();
    final data = await _xg!.score(_cred.studentId);
    final xm = ((data['student'] as Map?)?['xm'] ?? '').toString().trim();
    if (xm.isNotEmpty && _cred.realName.trim().isEmpty) {
      _cred.realName = xm;
      await AppState.I.persistDirect();
    }
    return {'ok': true, 'data': data};
  }

  Future<Map<String, dynamic>> activities() async {
    await _ensureXg();
    return {'ok': true, 'data': await _xg!.activitiesPayload()};
  }

  Future<Map<String, dynamic>> activityDetail(String aid) async {
    await _ensureXg();
    final data = await _xg!.fetchActivityDetail(aid);
    final hdms = (data['hdms'] ?? '').toString();
    return {
      'ok': true,
      'data': {
        'id': aid,
        'hdms': hdms,
        'quota': extractQuota(hdms),
        'signup': extractSignup(hdms),
      },
    };
  }

  // ==================== 教务：成绩 / 课表 / 考试 ====================

  Future<Map<String, dynamic>> grades({String? xnm, String? xqm}) async {
    await _ensureJwxt();
    final data = await _jwxt!.grades(_cred.studentId, xnm: xnm ?? '', xqm: xqm ?? '');
    return {'ok': true, 'data': data};
  }

  Future<Map<String, dynamic>> timetableWeek(String xnm, String xqm, int zs) async {
    await _ensureJwxt();
    final data = await _jwxt!.kbcx(_cred.studentId, xnm, xqm, zs);
    return {'ok': true, 'zs': zs, ...data};
  }

  Future<Map<String, dynamic>> exams(String xnm, String xqm) async {
    await _ensureJwxt();
    return {'ok': true, 'exams': await _jwxt!.exams(xnm, xqm)};
  }

  // ==================== 校付宝：校园码 / 电费 ====================

  Future<Map<String, dynamic>> ecard() async {
    final name = await _realName();
    final code = (await _epayClient.qrcode(_cred.studentId, name, _cred.payPassword))['code'];
    final balance = await _epayClient.cardBalance(_cred.studentId, name, _cred.payPassword);
    return {
      'ok': true,
      'data': {'code': code, 'card_balance': balance, 'refresh': 55},
    };
  }

  void _requireDorm() {
    if (!_cred.hasDorm) throw ApiError('请先在「连接设置 → 直连模式」填写寝室号（如「24号楼1016」）');
  }

  Future<Map<String, dynamic>> electricityQuery() async {
    _requireDorm();
    final name = await _realName();
    final data =
        await _epayClient.queryElectricity(_cred.studentId, name, _cred.payPassword, _cred.dorm);
    await _appendHistory(
      balance: (data['balance'] as num?)?.toDouble(),
      remain: (data['remain'] as num?)?.toDouble(),
      dorm: (data['dorm'] ?? _cred.dorm).toString(),
    );
    return {'ok': true, 'data': data};
  }

  /// ⚠️ 扣款：只调用一次，绝不自动重试。
  Future<Map<String, dynamic>> electricityRecharge(num amount) async {
    _requireDorm();
    final name = await _realName();
    final r = await _epayClient.rechargeElectricity(
        _cred.studentId, name, _cred.payPassword, _cred.dorm, amount.toDouble());
    await _appendHistory(
      balance: (r['balance'] as num?)?.toDouble(),
      remain: null,
      dorm: _cred.dorm,
      recharge: (r['amount'] as num?)?.toDouble() ?? amount.toDouble(),
    );
    return {
      'ok': true,
      'message': r['message'],
      'data': {
        'balance': r['balance'],
        'card_balance': r['balance'],
        'amount': r['amount'],
      },
    };
  }

  Future<Map<String, dynamic>> electricityHistory({int days = 90}) async {
    final sp = await SharedPreferences.getInstance();
    final records = _readHistory(sp);
    final since = DateTime.now().subtract(Duration(days: days.clamp(1, 365)));
    final out = records
        .where((r) => _parseTime(r['time'])?.isAfter(since) ?? false)
        .toList()
      ..sort((a, b) =>
          (_parseTime(a['time']) ?? DateTime(0)).compareTo(_parseTime(b['time']) ?? DateTime(0)));
    return {'ok': true, 'records': out};
  }

  // ==================== 测试连接 ====================

  /// 逐项探测学校系统可达性（教务 / 学工 / 校付宝），供连接设置页展示。
  Future<List<ProbeResult>> testConnection() async {
    final s = AppState.I.school;
    final out = <ProbeResult>[];
    out.add(await _probe('教务系统', () async {
      final c = JwxtClient(s.jwxtBase, aesKey: s.dektAesKey);
      try {
        final r = await c.probe();
        return r;
      } finally {
        c.dispose();
      }
    }));
    out.add(await _probe('学工系统', () async {
      final c = XgClient(authBase: s.authBase, xgBase: s.xgBase);
      try {
        final r = await c.probe();
        return r;
      } finally {
        c.dispose();
      }
    }));
    out.add(await _probe('校付宝', () async {
      final c = EpayClient(s.ecardBase);
      try {
        return await c.probe();
      } finally {
        c.dispose();
      }
    }));
    return out;
  }

  Future<ProbeResult> _probe(String name, Future<String?> Function() run) async {
    try {
      final detail = await run();
      return (name: name, ok: true, detail: detail ?? '可达');
    } on ApiError catch (e) {
      return (name: name, ok: false, detail: e.message);
    } catch (e) {
      return (name: name, ok: false, detail: '$e');
    }
  }

  static DateTime? _parseTime(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString().replaceFirst(' ', 'T'));

  static String _fmt(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> _readHistory(SharedPreferences sp) {
    try {
      final raw = sp.getString(_histKey);
      if (raw == null || raw.isEmpty) return [];
      final arr = jsonDecode(raw);
      if (arr is List) return arr.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    } catch (_) {}
    return [];
  }

  Future<void> _appendHistory({
    double? balance,
    double? remain,
    required String dorm,
    double recharge = 0,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final records = _readHistory(sp);
    records.add({
      'balance': balance,
      'remain': remain,
      'dorm': dorm,
      'time': _fmt(DateTime.now()),
      'recharge': recharge,
    });
    final cutoff = DateTime.now().subtract(const Duration(days: 366));
    records.removeWhere((r) => (_parseTime(r['time']) ?? DateTime.now()).isBefore(cutoff));
    await sp.setString(_histKey, jsonEncode(records));
  }
}
