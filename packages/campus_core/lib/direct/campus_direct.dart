import 'dart:async';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../api_error.dart';
import '../app_state.dart';
import 'activities_util.dart';
import 'course_select.dart';
import 'direct_history.dart';
import 'direct_probe.dart';
import 'epay.dart';
import 'jwxt.dart';
import 'school.dart';
import 'xg.dart';

export 'direct_probe.dart';

/// 验证码输入回调：UI 层注入（返回 null = 用户取消；refresh 用于「换一张」）。
typedef CaptchaPrompt = Future<String?> Function(
  Uint8List image,
  String hint,
  Future<Uint8List> Function() refresh, {
  String? error,
});

/// 直连模式总控：App 用校园凭据直接访问学校系统（教务 / 学工 / 校付宝），需设备在校园网或校内 VPN。
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

  /// 登录单飞：同一系统的并发调用共享同一个 Future，避免验证码弹窗叠着弹。
  Future<void>? _xgLogin;
  Future<void>? _jwxtLogin;

  /// 学校档案变化时重建三个客户端并清掉缓存。
  void _syncClients() {
    final s = AppState.I.school;
    final key = [
      s.name, s.authBase, s.jwxtBase, s.xgBase, s.ecardBase, s.dektAesKey,
      s.allowSelfSigned,
    ].join('|');
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
    return _jwxt ??= JwxtClient(
      AppState.I.school.jwxtBase,
      aesKey: AppState.I.school.dektAesKey,
      authBase: AppState.I.school.authBase,
      allowSelfSigned: AppState.I.school.allowSelfSigned,
    );
  }

  XgClient get _xgClient {
    _syncClients();
    return _xg ??= XgClient(
      authBase: AppState.I.school.authBase,
      xgBase: AppState.I.school.xgBase,
      allowSelfSigned: AppState.I.school.allowSelfSigned,
    );
  }

  EpayClient get _epayClient {
    _syncClients();
    return _epay ??= EpayClient(
      AppState.I.school.ecardBase,
      allowSelfSigned: AppState.I.school.allowSelfSigned,
    );
  }

  /// 断开直连会话：登录态与 Cookie 一并清掉，下次查询必须重新登录。
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

  /// 学校文案含「验证码」→ 只是码输错了，换一张重输；否则（密码/账号错）直接抛出。
  static bool _isCaptchaError(String msg) => msg.contains('验证码');

  /// 账号 / 密码被学校拒绝（不是验证码错）——教务账号密码登录走不通时改试统一身份认证。
  static bool _isCredentialError(String msg) =>
      msg.contains('密码') || msg.contains('账号') || msg.contains('用户名') || msg.contains('用户不存在');

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

  /// 教务会话 Cookie（name → value）：评教助手把这份登录态带进内嵌评教页。
  Future<Map<String, String>> jwxtCookies() async {
    await _ensureJwxt();
    return _jwxtClient.cookies();
  }

  Future<void> _loginJwxt() async {
    _requireCreds();
    if (_jwxt != null && _jwxt!.loggedIn) return;
    final client = _jwxtClient;
    if (await client.checkSession()) return;
    String? lastError;
    var casTried = false;
    var attempt = 0;
    while (attempt < 3) {
      attempt++;
      final image = await client.prepareLogin(_cred.studentId, _cred.password);
      if (image.isEmpty) {
        if (client.loggedIn) return; // CAS 自动放行，业务会话已建立
        throw ApiError('教务验证码获取失败，请稍后重试');
      }
      final hint = client.usingCasLogin ? '统一身份认证验证码' : '教务系统验证码';
      final text = await _askCaptcha(image, hint, () async {
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
        if (_isCaptchaError(lastError)) continue; // 换一张重输
        // 正方账号密码被拒：改走统一认证 SSO（jziotlogin），密码不变。
        if (!casTried && _isCredentialError(lastError) && await client.enableCasLogin()) {
          casTried = true;
          if (client.loggedIn) return; // SSO 直通：持久化的统一认证会话直接建好了业务会话
          attempt--; // 切换登录方式不算一次验证码尝试
          lastError = null;
          continue;
        }
        // 被拒且没有可用的 SSO 入口：把「教务密码可能不同于统一认证密码」说清楚。
        if (_isCredentialError(lastError)) {
          throw ApiError('$lastError。教务系统的密码可能与统一身份认证密码不是同一个'
              '（2026 级新生尤其常见）：请在校园网内到教务登录页点「忘记密码」自助重置，'
              '或向学校确认自己的教务密码后再试。');
        }
        rethrow;
      }
    }
    throw ApiError('教务系统登录失败：${lastError ?? '请稍后重试'}');
  }

  /// 会话可能在两次查询之间失效：一旦认出失效就自动重登一次再试。
  Future<T> _withReloginT<T>(
    Future<T> Function() run,
    Future<void> Function() login,
  ) async {
    try {
      return await run();
    } on ApiError catch (e) {
      if (!e.message.contains('失效')) rethrow;
      await login();
      return run();
    }
  }

  Future<Map<String, dynamic>> _withRelogin(
    Future<Map<String, dynamic>> Function() run,
    Future<void> Function() login,
  ) =>
      _withReloginT(run, login);

  /// 校付宝登录用的真实姓名：优先用填写值，其次查学工补全。
  Future<String> _realName() async {
    final filled = _cred.realName.trim();
    if (filled.isNotEmpty) return filled;
    if (_realNameCache.isNotEmpty) return _realNameCache;
    try {
      final s = await _withRelogin(() async {
        await _ensureXg();
        return _xg!.score(_cred.studentId);
      }, _ensureXg);
      final xm = ((s['student'] as Map?)?['xm'] ?? '').toString().trim();
      if (xm.isNotEmpty) {
        _realNameCache = xm;
        _cred.realName = xm;
        await AppState.I.persistDirect();
        return xm;
      }
    } catch (_) {}
    throw ApiError('校园卡登录需要真实姓名：请在「连接设置 → 直连模式」填写姓名'
        '（或在校园网下先查询第二课堂分数自动补全）');
  }

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

  Future<Map<String, dynamic>> score() => _withRelogin(() async {
        await _ensureXg();
        final data = await _xg!.score(_cred.studentId);
        final xm = ((data['student'] as Map?)?['xm'] ?? '').toString().trim();
        if (xm.isNotEmpty && _cred.realName.trim().isEmpty) {
          _cred.realName = xm;
          await AppState.I.persistDirect();
        }
        return {'ok': true, 'data': data};
      }, _ensureXg);

  Future<Map<String, dynamic>> activities() => _withRelogin(() async {
        await _ensureXg();
        return {'ok': true, 'data': await _xg!.activitiesPayload()};
      }, _ensureXg);

  /// 已报名的第二课堂活动（我的报名）。
  Future<Map<String, dynamic>> signedActivities() => _withRelogin(() async {
        await _ensureXg();
        return {'ok': true, 'activities': await _xg!.signedActivities()};
      }, _ensureXg);

  /// 第二课堂加分明细（每次活动参与记录 + 学分）。
  Future<Map<String, dynamic>> creditRecords() => _withRelogin(() async {
        await _ensureXg();
        return {'ok': true, 'records': await _xg!.creditRecords()};
      }, _ensureXg);

  Future<Map<String, dynamic>> activityDetail(String aid) => _withRelogin(() async {
        await _ensureXg();
        final data = await _xg!.fetchActivityDetail(aid);
        final hdms = (data['hdms'] ?? '').toString();
        String s(String k) => (data[k] ?? '').toString().trim();
        // 元信息空值不带，免得把列表项里的值盖掉（与后端同一条纪律）。
        return {
          'ok': true,
          'data': {
            'id': aid,
            if (s('hdmc').isNotEmpty) 'name': s('hdmc'),
            if (s('hdkssj').isNotEmpty) 'start': s('hdkssj'),
            if (s('hdjssj').isNotEmpty) 'end': s('hdjssj'),
            if (s('hdbmkssj').isNotEmpty) 'bm_start': s('hdbmkssj'),
            if (s('hdbmjssj').isNotEmpty) 'bm_end': s('hdbmjssj'),
            if (s('hddd').isNotEmpty) 'place': s('hddd'),
            if (s('zbfmc').isNotEmpty) 'host': s('zbfmc'),
            if (s('xqmc').isNotEmpty) 'campus': s('xqmc'),
            'hdms': hdms,
            // 学校详情接口的 bm = 本人是否已报名（实测 int 1 / str '1' 两态），归一成字符串比较
            'signed': '${data['bm']}' == '1',
            'quota': extractQuota(hdms),
            'signup': extractSignup(hdms),
          },
        };
      }, _ensureXg);

  /// 活动报名（写操作：只提交一次，报名内容由学校表单预填）。
  Future<Map<String, dynamic>> activitySignup(String aid) => _withRelogin(() async {
        await _ensureXg();
        return {'ok': true, 'data': await _xg!.signupActivity(aid)};
      }, _ensureXg);

  /// 扫码签到 / 签退（写操作：只提交一次）；hdId / hdActId 来自签到二维码的路径段。
  Future<Map<String, dynamic>> activitySignInOrSignOut(Object hdId, Object hdActId) =>
      _withRelogin(() async {
        await _ensureXg();
        return {'ok': true, 'data': await _xg!.signInOrSignOut(hdId, hdActId)};
      }, _ensureXg);

  /// 报名（培训）二维码的扫码签到（写操作：只提交一次）；hdId / pxId 来自二维码的路径段。
  Future<Map<String, dynamic>> activityTrainingSignIn(Object hdId, Object pxId) =>
      _withRelogin(() async {
        await _ensureXg();
        return {'ok': true, 'data': await _xg!.trainingSignIn(hdId, pxId)};
      }, _ensureXg);

  Future<Map<String, dynamic>> grades({String? xnm, String? xqm}) => _withRelogin(() async {
        await _ensureJwxt();
        final data = await _jwxt!.grades(_cred.studentId, xnm: xnm ?? '', xqm: xqm ?? '');
        return {'ok': true, 'data': data};
      }, _ensureJwxt);

  Future<Map<String, dynamic>> timetableWeek(String xnm, String xqm, int zs) =>
      _withRelogin(() async {
        await _ensureJwxt();
        final data = await _jwxt!.kbcx(_cred.studentId, xnm, xqm, zs);
        return {'ok': true, 'zs': zs, ...data};
      }, _ensureJwxt);

  Future<Map<String, dynamic>> exams(String xnm, String xqm) => _withRelogin(() async {
        await _ensureJwxt();
        return {'ok': true, 'exams': await _jwxt!.exams(xnm, xqm)};
      }, _ensureJwxt);

  /// 学业情况（学生学业情况查询）：整体统计 + 各类别学分要求 + 类别课程明细。
  Future<Map<String, dynamic>> academicStatus() => _withRelogin(() async {
        await _ensureJwxt();
        return {'ok': true, 'data': await _jwxt!.academicStatus()};
      }, _ensureJwxt);

  Future<List<CourseScope>> courseScopes() => _withReloginT(() async {
        await _ensureJwxt();
        return _jwxt!.courseScopes();
      }, _ensureJwxt);

  Future<List<CourseOffer>> courseOffers(
    CourseScope scope, {
    String keyword = '',
    int start = 0,
    int pageSize = 50,
  }) =>
      _withReloginT(() async {
        await _ensureJwxt();
        return _jwxt!.courseOffers(scope,
            keyword: keyword, start: start, pageSize: pageSize);
      }, _ensureJwxt);

  Future<List<CourseSection>> courseSections(CourseOffer offer) =>
      _withReloginT(() async {
        await _ensureJwxt();
        return _jwxt!.courseSections(offer);
      }, _ensureJwxt);

  /// 提交一次选课；名额满等业务结果用返回值表达，登录失效会抛「失效」触发重登重试。
  Future<CourseSelectResult> selectCourse(
          CourseOffer offer, CourseSection section) =>
      _withReloginT(() async {
        await _ensureJwxt();
        return _jwxt!.selectCourse(offer, section);
      }, _ensureJwxt);

  Future<List<SelectedCourse>> selectedCourses(CourseScope scope) =>
      _withReloginT(() async {
        await _ensureJwxt();
        return _jwxt!.selectedCourses(scope);
      }, _ensureJwxt);

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
    await appendElectricityHistory(
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
    await appendElectricityHistory(
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
    final records = readElectricityHistory(sp);
    final since = DateTime.now().subtract(Duration(days: days.clamp(1, 365)));
    final out = records
        .where((r) => parseHistoryTime(r['time'])?.isAfter(since) ?? false)
        .toList()
      ..sort((a, b) => (parseHistoryTime(a['time']) ?? DateTime(0))
          .compareTo(parseHistoryTime(b['time']) ?? DateTime(0)));
    return {'ok': true, 'records': out};
  }

  /// 逐项探测学校系统可达性（教务 / 学工 / 校付宝），供连接设置页展示。
  Future<List<ProbeResult>> testConnection() => testDirectConnection();
}
