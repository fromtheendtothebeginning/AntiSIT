import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_error.dart';
import 'app_state.dart';
import 'demo_data.dart';
import 'direct/campus_direct.dart';

export 'api_error.dart';

/// 统一 API 客户端，按「连接设置」的数据来源模式分流：
/// - 服务器模式：与网站同源的账号 JWT 鉴权
///   · 登录 = POST /api/login {username, password} → access_token（30 天 JWT）
///   · 401 → 先 POST /api/refresh 换新 token，失败再用记住的账号密码重登，均失败才抛出
///   · 隧道类接口全局串行：学校侧单 VPN 隧道约束
///   · 202 = VPN 建隧道中，等 retry_after 秒重试同一请求
///   · 电费充值 once=true：单次调用，绝不重试
/// - 直连模式：App 直接用校园凭据访问学校系统（CampusDirect），不走服务器
class ApiClient {
  static final ApiClient I = ApiClient._();
  ApiClient._();

  final http.Client _http = http.Client();
  Future<void> _queue = Future.value();
  Future<bool>? _recoverInFlight; // 并发 401 时共享同一次 refresh/重登，防止登录请求风暴触发 429

  /// 服务器模式的手动验证码弹窗：开放接口无法自动识码（未配识图模型等）时回 need_captcha，
  /// UI 层注入后弹出与直连模式同款的输入框（启动时与 CampusDirect 一起装一次）。
  CaptchaPrompt? captchaPrompt;

  /// 直连模式生效条件：演示模式优先（demo 时一切走本地假数据）。
  bool get _useDirect => !AppState.I.demo && AppState.I.direct;

  /// 服务器模式必填服务器地址；未配置直接引导，不发起无意义请求。
  void _requireServer() {
    if (AppState.I.serverUrl.isEmpty) {
      throw ApiError('尚未配置服务器地址：请在「我的 → 连接设置 → 服务器模式」填写');
    }
  }

  Future<T> _serial<T>(Future<T> Function() task) {
    final r = _queue.then((_) => task());
    _queue = r.then((_) {}, onError: (_) {});
    return r;
  }

  Uri _uri(String path, Map<String, String>? query) {
    var u = Uri.parse('${AppState.I.serverUrl}$path');
    if (query != null && query.isNotEmpty) {
      u = u.replace(queryParameters: {...u.queryParameters, ...query});
    }
    return u;
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool tunnel = false,
    bool once = false,
  }) async {
    final st = AppState.I;
    if (st.demo) return DemoData.handle(method, path, body: body, query: query);
    _requireServer();

    Future<Map<String, dynamic>> attempt() async {
      var recovered = false; // 每个请求只做一次鉴权恢复，防止 401→refresh→401 死循环
      var waited = 0;
      var captchaRounds = 0;
      while (true) {
        http.Response resp;
        try {
          final req = http.Request(method, _uri(path, query));
          final token = st.token;
          if (token != null) req.headers['Authorization'] = 'Bearer $token';
          if (body != null) {
            req.headers['Content-Type'] = 'application/json';
            req.body = jsonEncode(body);
          }
          final streamed =
              await _http.send(req).timeout(const Duration(seconds: 60));
          resp = await http.Response.fromStream(streamed)
              .timeout(const Duration(seconds: 60));
        } on TimeoutException {
          throw ApiError('请求超时，首次调用可能正在建立校园网隧道，请稍后重试');
        } catch (e) {
          throw ApiError('网络错误，请检查网络或服务器地址');
        }

        if (resp.statusCode == 202 && !once) {
          if (waited > 120) throw ApiError('校园网隧道建立超时，请稍后重试');
          var retryAfter = 5;
          try {
            final j = jsonDecode(utf8.decode(resp.bodyBytes));
            if (j is Map && j['retry_after'] is num) retryAfter = (j['retry_after'] as num).toInt();
          } catch (_) {}
          waited += retryAfter;
          await Future.delayed(Duration(seconds: retryAfter));
          continue;
        }

        if (resp.statusCode == 401 && !once) {
          // 并发 401 共享同一次恢复（refresh → 记住密码重登），避免重复打 /api/login；
          // 恢复后仍 401 说明 token 确实不被接受，直接抛出服务端 detail，不再无限重试
          if (!recovered) {
            recovered = true;
            if (await _recoverAuth()) continue;
          }
        }

        Map<String, dynamic>? j;
        try {
          final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
          if (decoded is Map<String, dynamic>) j = decoded;
        } catch (_) {}

        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          final detail = j?['detail'];
          String msg;
          if (detail is String && detail.isNotEmpty) {
            msg = detail;
          } else if (detail != null) {
            msg = '参数校验失败：${jsonEncode(detail)}';
          } else if (resp.statusCode == 401) {
            msg = '登录已过期，请重新登录';
          } else {
            msg = '请求失败（${resp.statusCode}）';
          }
          throw ApiError(msg, resp.statusCode);
        }
        if (j?['need_captcha'] == true) {
          // 服务器自动识码走不通（未配识图模型/识图失败）：弹手动验证码，登录完成后重试原请求
          if (++captchaRounds > 3) throw ApiError('验证码登录未完成，请稍后重试');
          await _solveCaptcha(j!);
          continue;
        }
        return j ?? <String, dynamic>{};
      }
    }

    return tunnel ? _serial(attempt) : attempt();
  }

  /// need_captcha 手动验证码流程：弹输入框 → POST /api/campus-open/captcha 提交；
  /// 学校回「验证码」类错误则换一张（GET 同路径）再弹，其他错误（密码/账号错）直接抛出。
  /// 注意：提交/换一张绝不能 tunnel:true——原请求正占着隧道串行队列，排队会死等自己。
  Future<void> _solveCaptcha(Map<String, dynamic> j) async {
    final mode = (j['mode'] ?? 'xg').toString();
    final hint = mode == 'jwxt' ? '教务系统验证码' : '统一身份认证验证码';
    var image = base64Decode((j['captcha_base64'] ?? '').toString());
    String? lastError;
    for (var round = 0; round < 3; round++) {
      final prompt = captchaPrompt;
      if (prompt == null) throw ApiError('$hint：需要输入验证码，但当前界面无法弹出输入框');
      final text = await prompt(image, hint, () async {
        final r = await _call('GET', '/api/campus-open/captcha',
            query: {'mode': mode}, once: true);
        final b64 = (r['captcha_base64'] ?? '').toString();
        return b64.isEmpty ? image : base64Decode(b64); // 期间已登录成功：原样返回，外层重试即可
      }, error: lastError);
      if (text == null || text.trim().isEmpty) throw ApiError('已取消验证码输入');
      try {
        await _call('POST', '/api/campus-open/captcha',
            body: {'mode': mode, 'captcha': text.trim()}, once: true);
        return;
      } on ApiError catch (e) {
        lastError = e.message;
        if (!lastError.contains('验证码')) rethrow; // 密码/账号错直接失败，不反复弹窗
        final r = await _call('GET', '/api/campus-open/captcha',
            query: {'mode': mode}, once: true);
        final b64 = (r['captcha_base64'] ?? '').toString();
        if (b64.isEmpty) rethrow;
        image = base64Decode(b64);
      }
    }
    throw ApiError('$hint：连续 3 次验证码未通过，请稍后重试');
  }

  /// 单飞恢复登录态：refresh 成功或用记住的密码重登成功返回 true。
  /// 并发调用只发起一次网络请求，全部等待同一结果。
  Future<bool> _recoverAuth() {
    return _recoverInFlight ??= _recoverAuthImpl().whenComplete(() => _recoverInFlight = null);
  }

  Future<bool> _recoverAuthImpl() async {
    final st = AppState.I;
    final newToken = await refresh();
    if (newToken != null) return true;
    if (st.hasCreds) {
      try {
        final r = await login(st.username!, st.password!);
        final t = r['access_token'];
        if (t is String && t.isNotEmpty) {
          await st.saveLogin(token: t, username: st.username!, password: st.password);
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// 服务器模式：服务器账号登录换 JWT。失败抛 ApiError（401 账号密码错误 / 429 限流）。
  Future<Map<String, dynamic>> login(String username, String password) async {
    final st = AppState.I;
    if (st.demo) {
      await Future.delayed(const Duration(milliseconds: 500));
      return {'ok': true, 'access_token': 'demo-token'};
    }
    if (st.direct) {
      throw ApiError('当前是直连模式：请在「连接设置」填写校园凭据，无需服务器账号');
    }
    _requireServer();
    http.Response resp;
    try {
      resp = await _http
          .post(
            _uri('/api/login', null),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw ApiError('登录超时，请检查网络');
    } catch (e) {
      throw ApiError('网络错误，请检查网络或服务器地址');
    }
    Map<String, dynamic>? j;
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map<String, dynamic>) j = decoded;
    } catch (_) {}
    if (resp.statusCode != 200 || j == null) {
      final detail = j?['detail'];
      throw ApiError(
          detail is String && detail.isNotEmpty ? detail : '登录失败（${resp.statusCode}）',
          resp.statusCode);
    }
    return j;
  }

  /// 滑动续期：用当前 token 换新 token；失败返回 null（不影响调用方）。
  Future<String?> refresh() async {
    final st = AppState.I;
    if (st.demo || st.direct) return null;
    final token = st.token;
    if (token == null) return null;
    try {
      final resp = await _http
          .post(_uri('/api/refresh', null),
              headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(resp.bodyBytes));
      final t = j is Map ? j['access_token'] : null;
      if (t is String && t.isNotEmpty) {
        await st.saveLogin(
            token: t, username: st.username ?? '', password: st.password);
        return t;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> status() => _useDirect
      ? CampusDirect.I.status()
      : _call('GET', '/api/campus-open/status');

  /// 断开 VPN 会话（释放隧道，下次数据调用自动重连）；直连模式则清学校系统会话。
  Future<void> disconnect() async {
    if (_useDirect) {
      await CampusDirect.I.disconnect();
      return;
    }
    try {
      await _call('POST', '/api/campus-open/disconnect', once: true);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> score() => _useDirect
      ? CampusDirect.I.score()
      : _call('GET', '/api/campus-open/score', tunnel: true);

  /// xnm/xqm 均不传时返回全部学期成绩 + terms 列表。
  Future<Map<String, dynamic>> grades({String? xnm, String? xqm}) => _useDirect
      ? CampusDirect.I.grades(xnm: xnm, xqm: xqm)
      : _call(
          'GET',
          '/api/campus-open/grades',
          query: {
            if (xnm != null && xnm.isNotEmpty) 'xnm': xnm,
            if (xqm != null && xqm.isNotEmpty) 'xqm': xqm,
          },
          tunnel: true,
        );

  Future<Map<String, dynamic>> activities() => _useDirect
      ? CampusDirect.I.activities()
      : _call('GET', '/api/campus-open/activities', tunnel: true);

  Future<Map<String, dynamic>> activityDetail(String aid) => _useDirect
      ? CampusDirect.I.activityDetail(aid)
      : _call('GET', '/api/campus-open/activities/$aid', tunnel: true);

  Future<Map<String, dynamic>> timetableWeek(String xnm, String xqm, int zs) =>
      _useDirect
          ? CampusDirect.I.timetableWeek(xnm, xqm, zs)
          : _call('POST', '/api/campus-open/timetable/week',
              body: {'xnm': xnm, 'xqm': xqm, 'zs': zs}, tunnel: true);

  Future<Map<String, dynamic>> exams(String xnm, String xqm) => _useDirect
      ? CampusDirect.I.exams(xnm, xqm)
      : _call('POST', '/api/campus-open/timetable/exams',
          body: {'xnm': xnm, 'xqm': xqm}, tunnel: true);

  Future<Map<String, dynamic>> ecard() =>
      _useDirect ? CampusDirect.I.ecard() : _call('GET', '/api/campus-open/ecard');

  Future<Map<String, dynamic>> electricityQuery() => _useDirect
      ? CampusDirect.I.electricityQuery()
      : _call('POST', '/api/campus-open/electricity/query');

  /// 电费历史：服务器模式取站内记录，直连模式取本机记录（均升序，recharge>0 表示当天有充值）。
  Future<Map<String, dynamic>> electricityHistory({int days = 90}) => _useDirect
      ? CampusDirect.I.electricityHistory(days: days)
      : _call('GET', '/api/campus-open/electricity/history', query: {'days': '$days'});

  /// ⚠️ 扣款接口：单次调用绝不重试；超时后请先查余额确认。
  Future<Map<String, dynamic>> electricityRecharge(num amount) => _useDirect
      ? CampusDirect.I.electricityRecharge(amount)
      : _call('POST', '/api/campus-open/electricity/recharge',
          body: {'amount': amount}, once: true);

  /// 课程表云端存储（站内接口，与网站共用同一份数据）；直连模式没有云端，静默降级为本地。
  Future<Map<String, dynamic>> timetableCloudGet() async {
    if (_useDirect) return {'ok': true, 'data': null};
    return _call('GET', '/api/timetable');
  }

  Future<void> timetableCloudPut(Map<String, dynamic> data) async {
    if (_useDirect) return;
    await _call('PUT', '/api/timetable', body: {'data': data});
  }
}
