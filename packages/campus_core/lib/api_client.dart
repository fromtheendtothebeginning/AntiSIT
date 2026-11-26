import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_error.dart';
import 'app_state.dart';
import 'demo_data.dart';
import 'direct/campus_direct.dart';
import 'direct/course_select.dart';

export 'api_error.dart';

/// 统一 API 客户端，按「连接设置」的数据来源模式分流：
/// - 服务器模式：账号 JWT 鉴权；401 先 refresh 再用记住的密码重登；隧道类接口全局串行
///   （学校侧单 VPN 隧道约束）；202 = 建隧道中，等 retry_after 秒重试；充值 once=true 绝不重试。
/// - 直连模式：App 直接用校园凭据访问学校系统（CampusDirect），不走服务器。
class ApiClient {
  static final ApiClient I = ApiClient._();
  ApiClient._();

  final http.Client _http = http.Client();
  Future<void> _queue = Future.value();
  Future<bool>? _recoverInFlight; // 并发 401 时共享同一次 refresh/重登，防止登录请求风暴触发 429

  /// 正卡在「202 = 服务器在建校园网隧道」等待里的请求数（>0 = 建隧道中）。
  /// 计数而不是布尔：并发请求可能同时在等，页面据此显示「正在建立校园网隧道…」。
  static final ValueNotifier<int> tunnelWarmup = ValueNotifier<int>(0);

  static void _warmupStart() => tunnelWarmup.value = tunnelWarmup.value + 1;

  static void _warmupEnd() {
    if (tunnelWarmup.value > 0) tunnelWarmup.value = tunnelWarmup.value - 1;
  }

  /// 服务器模式的手动验证码弹窗：开放接口无法自动识码时由 UI 层注入。
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

    Future<Map<String, dynamic>> attempt(void Function() onWarm) async {
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
          throw ApiError('请求超时，首次调用可能正在建立校园网隧道，请稍后重试', null, true);
        } catch (e) {
          throw ApiError('网络错误，请检查网络或服务器地址', null, true);
        }

        if (resp.statusCode == 202 && once) {
          // once = 绝不重试的写操作（充值 / 断隧道）：202 只表示「服务器还在建隧道」，
          // 请求根本没被处理。不能落进下面的 2xx 成功分支，否则调用方会拿着
          // {"retry_after":5} 当充值成功提示用户。
          throw ApiError('校园网隧道尚未建立，本次请求未执行，请稍后重试', 202, false);
        }

        if (resp.statusCode == 202 && !once) {
          if (waited > 120) throw ApiError('校园网隧道建立超时，请稍后重试');
          onWarm(); // 建隧道中：界面据此显示「正在建立校园网隧道…」
          var retryAfter = 5;
          try {
            final j = jsonDecode(utf8.decode(resp.bodyBytes));
            if (j is Map && j['retry_after'] is num) retryAfter = (j['retry_after'] as num).toInt();
          } catch (_) {}
          // 服务端回 0 / 负数（或巨值）时不能让循环空转：夹到 1-60 秒。
          retryAfter = retryAfter.clamp(1, 60);
          waited += retryAfter;
          await Future.delayed(Duration(seconds: retryAfter));
          continue;
        }

        if (resp.statusCode == 401 && !once) {
          // 并发 401 共享同一次恢复；恢复后仍 401 说明 token 确实不被接受，直接抛出
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
          // 服务器自动识码走不通：弹手动验证码，登录完成后重试原请求
          if (++captchaRounds > 3) throw ApiError('验证码登录未完成，请稍后重试');
          await _solveCaptcha(j!);
          continue;
        }
        return j ?? <String, dynamic>{};
      }
    }

    // 建隧道期间让界面有话可说：这轮结束后（成功 / 报错 / 超时）收掉计数
    var warming = false;
    Future<Map<String, dynamic>> run() async {
      void onWarm() {
        if (warming) return;
        warming = true;
        _warmupStart();
      }

      try {
        return await attempt(onWarm);
      } finally {
        if (warming) _warmupEnd();
      }
    }

    return tunnel ? _serial(run) : run();
  }

  /// need_captcha 手动验证码流程：弹输入框 → 提交；验证码类错误换一张再弹，其他错误直接抛。
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

  /// 内嵌教务网页（评教助手）需要的会话材料。
  ///
  /// 直连模式用 App 本地已登录的教务 Cookie；服务器模式用服务器代连时的教务 Cookie，
  /// 且 WebView 必须经 [serverWebProxy] 的代理出去，否则外网打不开教务页。
  Future<JwxtWebSession> jwxtWebSession() async {
    if (_useDirect) {
      return JwxtWebSession(cookies: await CampusDirect.I.jwxtCookies());
    }
    if (AppState.I.demo) return const JwxtWebSession();
    final r = await _call('GET', '/api/campus-open/jwxt/web', tunnel: true);
    return JwxtWebSession.fromServer(r['data']);
  }

  /// 服务器模式的校园隧道网页代理（`http://host:port`）；直连 / 演示 / 隧道没连上返回空串。
  Future<String> serverWebProxy() async {
    if (_useDirect || AppState.I.demo) return '';
    return campusProxyFromStatus(await status());
  }

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

  /// 已报名的第二课堂活动（我的报名）。
  Future<Map<String, dynamic>> signedActivities() => _useDirect
      ? CampusDirect.I.signedActivities()
      : _call('GET', '/api/campus-open/activities/signed', tunnel: true);

  /// 第二课堂加分明细（每次活动参与记录 + 学分）。
  Future<Map<String, dynamic>> creditRecords() => _useDirect
      ? CampusDirect.I.creditRecords()
      : _call('GET', '/api/campus-open/score/credits', tunnel: true);

  Future<Map<String, dynamic>> activityDetail(String aid) => _useDirect
      ? CampusDirect.I.activityDetail(aid)
      : _call('GET', '/api/campus-open/activities/$aid', tunnel: true);

  /// 活动报名（写操作）：超时 / 网络错误后**绝不自动重发**，先引导用户到学工系统确认。
  /// 202 / 401 / need_captcha 的重试安全（请求还没到达学校），走 [_call] 默认循环。
  Future<Map<String, dynamic>> activitySignup(String aid) => _useDirect
      ? CampusDirect.I.activitySignup(aid)
      : _call('POST', '/api/campus-open/activities/$aid/signup',
          body: const {}, tunnel: true);

  /// 扫码签到 / 签退（学校按场次判定方向，返回判定原文）。写操作：只提交一次、绝不重试。
  Future<Map<String, dynamic>> activitySignInOrSignOut(String hdId, String hdActId) =>
      _useDirect
          ? CampusDirect.I.activitySignInOrSignOut(hdId, hdActId)
          : _call('POST', '/api/campus-open/activities/sign',
              body: {'hdId': hdId, 'hdActId': hdActId}, tunnel: true);

  /// 报名（培训）二维码的扫码签到。写操作：只提交一次、绝不重试。
  Future<Map<String, dynamic>> activityTrainingSignIn(String hdId, String pxId) =>
      _useDirect
          ? CampusDirect.I.activityTrainingSignIn(hdId, pxId)
          : _call('POST', '/api/campus-open/activities/train-sign',
              body: {'hdId': hdId, 'pxId': pxId}, tunnel: true);

  Future<Map<String, dynamic>> timetableWeek(String xnm, String xqm, int zs) =>
      _useDirect
          ? CampusDirect.I.timetableWeek(xnm, xqm, zs)
          : _call('POST', '/api/campus-open/timetable/week',
              body: {'xnm': xnm, 'xqm': xqm, 'zs': zs}, tunnel: true);

  Future<Map<String, dynamic>> exams(String xnm, String xqm) => _useDirect
      ? CampusDirect.I.exams(xnm, xqm)
      : _call('POST', '/api/campus-open/timetable/exams',
          body: {'xnm': xnm, 'xqm': xqm}, tunnel: true);

  /// 学业情况（N105515）：整体统计 + 培养方案类别学分要求与类别课程明细。
  Future<Map<String, dynamic>> academicStatus() => _useDirect
      ? CampusDirect.I.academicStatus()
      : _call('GET', '/api/campus-open/academic', tunnel: true);

  // ── 抢课（正方 9.0 选课）：暂只实现直连模式，开放接口还没有对应端点 ──

  void _requireDirectSelection() {
    // 演示模式用本地假数据，不算「直连」，不拦
    if (AppState.I.demo) return;
    if (!_useDirect) {
      throw ApiError('抢课目前只支持直连模式：请到「我的 → 连接设置」切换到直连模式，'
          '并在校园网 / 校内 VPN 下使用');
    }
  }

  Future<List<CourseScope>> courseScopes() {
    if (AppState.I.demo) return Future.value(DemoData.courseScopes());
    _requireDirectSelection();
    return CampusDirect.I.courseScopes();
  }

  Future<List<CourseOffer>> courseOffers(
    CourseScope scope, {
    String keyword = '',
    int start = 0,
    int pageSize = 50,
  }) {
    if (AppState.I.demo) {
      return Future.value(DemoData.courseOffers(scope,
          keyword: keyword, start: start, pageSize: pageSize));
    }
    _requireDirectSelection();
    return CampusDirect.I.courseOffers(scope,
        keyword: keyword, start: start, pageSize: pageSize);
  }

  Future<List<CourseSection>> courseSections(CourseOffer offer) {
    if (AppState.I.demo) return Future.value(DemoData.courseSections(offer));
    _requireDirectSelection();
    return CampusDirect.I.courseSections(offer);
  }

  Future<CourseSelectResult> selectCourse(
      CourseOffer offer, CourseSection section) {
    if (AppState.I.demo) {
      return Future.value(DemoData.selectCourse(offer, section));
    }
    _requireDirectSelection();
    return CampusDirect.I.selectCourse(offer, section);
  }

  Future<List<SelectedCourse>> selectedCourses(CourseScope scope) {
    if (AppState.I.demo) {
      return Future.value(DemoData.selectedCourses(scope));
    }
    _requireDirectSelection();
    return CampusDirect.I.selectedCourses(scope);
  }

  Future<Map<String, dynamic>> ecard() =>
      _useDirect ? CampusDirect.I.ecard() : _call('GET', '/api/campus-open/ecard');

  Future<Map<String, dynamic>> electricityQuery() => _useDirect
      ? CampusDirect.I.electricityQuery()
      : _call('POST', '/api/campus-open/electricity/query');

  /// 电费历史：服务器模式取站内记录，直连模式取本机记录（均升序，recharge>0 = 当天有充值）。
  Future<Map<String, dynamic>> electricityHistory({int days = 90}) => _useDirect
      ? CampusDirect.I.electricityHistory(days: days)
      : _call('GET', '/api/campus-open/electricity/history', query: {'days': '$days'});

  /// ⚠️ 扣款接口：单次调用绝不重试；超时后请先查余额确认。
  Future<Map<String, dynamic>> electricityRecharge(num amount) => _useDirect
      ? CampusDirect.I.electricityRecharge(amount)
      : _call('POST', '/api/campus-open/electricity/recharge',
          body: {'amount': amount}, once: true);

  /// 课程表云端存储（站内接口，与网站共用同一份数据）；直连模式静默降级为本地。
  Future<Map<String, dynamic>> timetableCloudGet() async {
    if (_useDirect) return {'ok': true, 'data': null};
    return _call('GET', '/api/timetable');
  }

  Future<void> timetableCloudPut(Map<String, dynamic> data) async {
    if (_useDirect) return;
    await _call('PUT', '/api/timetable', body: {'data': data});
  }
}

/// 内嵌教务网页的会话材料（见 [ApiClient.jwxtWebSession]）。
class JwxtWebSession {
  const JwxtWebSession({this.cookies = const {}, this.base = ''});

  /// 教务系统 Cookie（name → value）。
  final Map<String, String> cookies;

  /// 服务器返回的教务域名；空 = 用 App 学校档案里的地址。
  final String base;

  /// 解析服务器 `/api/campus-open/jwxt/web` 的 data；结构不对时返回空会话。
  factory JwxtWebSession.fromServer(Object? data) {
    final map = data is Map ? data : const {};
    final cookies = <String, String>{};
    final raw = map['cookies'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v != null) cookies['$k'] = '$v';
      });
    }
    return JwxtWebSession(
      cookies: cookies,
      base: '${map['jwxt_base'] ?? ''}'.trim(),
    );
  }
}

/// 从 `/api/campus-open/status` 的响应里取校园隧道网页代理（`http://host:port`）。
/// 隧道没连上、缺端口、host 为空或是回环地址时返回空串（回环只对服务器自己有意义）。
String campusProxyFromStatus(Object? status) {
  final map = status is Map ? status : const {};
  final session = map['session'];
  if (session is! Map || session['connected'] != true) return '';
  final host = '${session['host'] ?? ''}'
      .trim()
      .replaceFirst(RegExp(r'^https?://'), '')
      .replaceAll(RegExp(r'/+$'), '');
  final port = session['http_port'];
  final loopback = host == 'localhost' || host.startsWith('127.');
  if (host.isEmpty || loopback || port is! num || port <= 0) return '';
  return 'http://$host:${port.toInt()}';
}
