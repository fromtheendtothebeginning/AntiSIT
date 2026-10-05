import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_state.dart';
import 'demo_data.dart';

class ApiError implements Exception {
  final String message;
  final int? code;
  ApiError(this.message, [this.code]);
  @override
  String toString() => message;
}

/// 统一 API 客户端（鉴权与 anticraft 网站同源 JWT）。
/// - 登录 = POST /api/login {username, password} → access_token（30 天 JWT）
/// - 401 → 先 POST /api/refresh 换新 token，失败再用记住的账号密码重登，均失败才抛出
/// - 隧道类接口全局串行：学校侧单 VPN 隧道约束
/// - 202 = VPN 建隧道中，等 retry_after 秒重试同一请求
/// - 电费充值 once=true：单次调用，绝不重试
class ApiClient {
  static final ApiClient I = ApiClient._();
  ApiClient._();

  final http.Client _http = http.Client();
  Future<void> _queue = Future.value();
  Future<bool>? _recoverInFlight; // 并发 401 时共享同一次 refresh/重登，防止登录请求风暴触发 429

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

    Future<Map<String, dynamic>> attempt() async {
      var recovered = false; // 每个请求只做一次鉴权恢复，防止 401→refresh→401 死循环
      var waited = 0;
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
        return j ?? <String, dynamic>{};
      }
    }

    return tunnel ? _serial(attempt) : attempt();
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

  /// anticraft 账号登录换 JWT。失败抛 ApiError（401 账号密码错误 / 429 限流）。
  Future<Map<String, dynamic>> login(String username, String password) async {
    final st = AppState.I;
    if (st.demo) {
      await Future.delayed(const Duration(milliseconds: 500));
      return {'ok': true, 'access_token': 'demo-token'};
    }
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
    if (st.demo) return null;
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

  Future<Map<String, dynamic>> status() =>
      _call('GET', '/api/campus-open/status');

  /// 断开 VPN 会话（释放隧道，下次数据调用自动重连）。
  Future<void> disconnect() async {
    try {
      await _call('POST', '/api/campus-open/disconnect', once: true);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> score() =>
      _call('GET', '/api/campus-open/score', tunnel: true);

  /// xnm/xqm 均不传时返回全部学期成绩 + terms 列表。
  Future<Map<String, dynamic>> grades({String? xnm, String? xqm}) => _call(
        'GET',
        '/api/campus-open/grades',
        query: {
          if (xnm != null && xnm.isNotEmpty) 'xnm': xnm,
          if (xqm != null && xqm.isNotEmpty) 'xqm': xqm,
        },
        tunnel: true,
      );

  Future<Map<String, dynamic>> activities() =>
      _call('GET', '/api/campus-open/activities', tunnel: true);

  Future<Map<String, dynamic>> activityDetail(String aid) =>
      _call('GET', '/api/campus-open/activities/$aid', tunnel: true);

  Future<Map<String, dynamic>> timetableWeek(String xnm, String xqm, int zs) =>
      _call('POST', '/api/campus-open/timetable/week',
          body: {'xnm': xnm, 'xqm': xqm, 'zs': zs}, tunnel: true);

  Future<Map<String, dynamic>> exams(String xnm, String xqm) =>
      _call('POST', '/api/campus-open/timetable/exams',
          body: {'xnm': xnm, 'xqm': xqm}, tunnel: true);

  Future<Map<String, dynamic>> ecard() =>
      _call('GET', '/api/campus-open/ecard');

  Future<Map<String, dynamic>> electricityQuery() =>
      _call('POST', '/api/campus-open/electricity/query');

  /// 电费历史（站内记录，无需隧道）：records 升序，recharge>0 表示当天有充值。
  Future<Map<String, dynamic>> electricityHistory({int days = 90}) =>
      _call('GET', '/api/campus-open/electricity/history',
          query: {'days': '$days'});

  /// ⚠️ 扣款接口：单次调用绝不重试；超时后请先查余额确认。
  Future<Map<String, dynamic>> electricityRecharge(num amount) =>
      _call('POST', '/api/campus-open/electricity/recharge',
          body: {'amount': amount}, once: true);

  /// 课程表云端存储（站内接口，与网站共用同一份数据）。
  Future<Map<String, dynamic>> timetableCloudGet() => _call('GET', '/api/timetable');

  Future<void> timetableCloudPut(Map<String, dynamic> data) async {
    await _call('PUT', '/api/timetable', body: {'data': data});
  }
}
