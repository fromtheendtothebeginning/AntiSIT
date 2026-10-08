import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import 'crypto.dart';
import 'mock_captcha.dart';
import 'school.dart';
import 'sm4.dart';

// ⚠️ 仅调试用的本地模拟校园服务（release 不启用；连接设置页入口也只在 kDebugMode 出现）。
//
// 为什么需要它：直连模式要访问学校内网（教务 / 统一认证 / 学工），模拟器没有校园网，
// 真实链路根本跑不起来——验证码弹窗、Cookie 会话、登录失败重试这些都测不到。
// 这里在 App 进程内起一个只监听 127.0.0.1 的 HTTP 服务，按学校系统的**真实协议**应答：
//
//   正方教务 /jwglxt/…            登录页带 csrftoken；公钥 RSA 加密密码；/kaptcha 图形验证码；
//                                成功 302 置会话 Cookie，失败 200 且在 id="tips" 给出原文。
//   统一认证 /authserver/…        CAS 表单（execution/lt/salt）+ captcha.html 图形验证码，
//                                密码 AES-128-CBC 加密提交；会话有效后 check.zf 不再跳登录页。
//   学工     /zftal-xgxt-web/…    未登录 302 跳 CAS（客户端 _sessionLost 依赖这个语义）。
//   校付宝   /openservice/…       SM4 加密支付密码换 token；token 失效回 403。
//
// 校验是真校验：RSA / AES / SM4 都用 App 同一套算法解密回来比对凭据，
// 所以走通模拟服务 ≈ 走通了真实加密与表单链路，差别只在校内网络可达性。
class MockCampusServer {
  static final MockCampusServer instance = MockCampusServer._();
  MockCampusServer._();

  /// 模拟学校档案名（连接设置里一眼看出在跑本地服务）。
  static const String schoolName = '本地模拟学校（调试）';

  /// 模拟凭据：连接设置「使用本地模拟服务」一键填入，与 mock 校验的一致。
  static const String studentId = '25110001';
  static const String password = 'sit@123456';
  static const String payPassword = '888888';
  static const String realName = '张三';
  static const String dorm = '24号楼1016';

  static const List<int> _ports = [18780, 18781, 18782, 18783];

  HttpServer? _server;
  int _port = _ports.first;
  Future<void>? _starting;

  /// 最近一次下发的验证码（调试 / 自动化测试取用）。
  String? debugJwxtCaptcha;
  String? debugAuthCaptcha;

  /// 测试用：把登录页加密盐的 value 写到 id 之前（页面改版时属性顺序会变，解析不能依赖顺序）。
  bool debugFlipSaltAttribute = false;

  /// 测试用：教务登录失败时改回这段「页面里没有可读错误文案」的 HTML（SIT 新版登录页就是
  /// 错误由 JS 渲染、服务端 HTML 里没有原因）。null = 默认的 #tips 文案。
  String? debugJwxtLoginFailBody;

  bool get running => _server != null;
  Uri get baseUri => Uri.parse('http://127.0.0.1:$_port');
  String get baseUrl => baseUri.toString();

  /// 模拟学校档案：四个系统都指向本机这一个服务（按路径区分）。
  SchoolProfile profile() => SchoolProfile(
        name: schoolName,
        authBase: '$baseUrl/authserver',
        jwxtBase: baseUrl,
        xgBase: baseUrl,
        ecardBase: baseUrl,
      );

  /// 启动（幂等）。端口几个候选，全部占用则抛错。
  Future<void> start() {
    if (_server != null) return Future.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    Object? lastError;
    for (final p in _ports) {
      try {
        final s = await HttpServer.bind(InternetAddress.loopbackIPv4, p);
        s.listen(_handle);
        _server = s;
        _port = p;
        debugPrint('[mock] 本地模拟校园服务已启动：$baseUrl');
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('本地模拟服务启动失败（端口 ${_ports.join("/")} 均被占用）：$lastError');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _sessions.clear();
  }

  /// 调试启动时调用：当前学校档案指向本机回环才启动（真实学校档案不会命中）。
  Future<void> ensureIfConfigured() async {
    if (!kDebugMode || _server != null) return;
    if (!isLoopbackBase(AppState.I.school.jwxtBase)) return;
    await start();
  }

  static bool isLoopbackBase(String url) {
    if (url.isEmpty) return false;
    try {
      final h = Uri.parse(url).host;
      return h == '127.0.0.1' || h == 'localhost' || h == '::1';
    } catch (_) {
      return false;
    }
  }

  // ==================== 会话 ====================

  final Map<String, _MockSession> _sessions = {};

  _MockSession _session(HttpRequest req, HttpResponse res) {
    String? sid;
    for (final c in req.cookies) {
      if (c.name == 'MOCKSID') sid = c.value;
    }
    var s = sid == null ? null : _sessions[sid];
    if (s == null) {
      sid = 'mock-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(9999)}';
      s = _MockSession();
      _sessions[sid] = s;
      res.headers.add('Set-Cookie', 'MOCKSID=$sid; Path=/; HttpOnly');
    }
    return s;
  }

  // ==================== 请求分发 ====================

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final path = req.uri.path;
    try {
      final raw = await utf8.decoder.bind(req).join();
      final isJson = (req.headers.contentType?.mimeType ?? '').contains('json');
      final json = isJson && raw.isNotEmpty
          ? (jsonDecode(raw) as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      final form = isJson ? const <String, String>{} : Uri.splitQueryString(raw);
      final s = _session(req, res);

      if (path.startsWith('/jwglxt')) return await _jwxt(req, res, s, path, form);
      if (path.startsWith('/authserver')) return await _cas(req, res, s, path, form);
      if (path.startsWith('/zftal-xgxt-web')) return await _xg(req, res, s, path, form);
      if (path.startsWith('/openservice')) return await _epay(req, res, s, path, json);
      if (path.startsWith('/epeortal')) return _html(res, '<html><body>校付宝 H5（mock）</body></html>');
      _text(res, 404, 'mock: 未实现的路径 $path', 'text/plain; charset=utf-8');
    } catch (e) {
      debugPrint('[mock] 处理 $path 出错：$e');
      _text(res, 500, 'mock 内部错误：$e', 'text/plain; charset=utf-8');
    }
  }

  // ==================== 正方教务 ====================

  Future<void> _jwxt(
    HttpRequest req,
    HttpResponse res,
    _MockSession s,
    String path,
    Map<String, String> form,
  ) async {
    switch (path) {
      // 登录：GET 出登录页（含 csrftoken），POST 校验凭据
      case '/jwglxt/xtgl/login_slogin.html':
        if (req.method == 'POST') {
          final yzm = (form['yzm'] ?? '').toUpperCase();
          if (yzm.isEmpty || yzm != (s.jwxtCaptcha ?? '').toUpperCase()) {
            return _jwxtLoginFail(res, '验证码错误');
          }
          if ((form['yhm'] ?? '') != studentId) return _jwxtLoginFail(res, '用户名或密码错误');
          if (_rsaDecrypt(form['mm'] ?? '') != password) {
            return _jwxtLoginFail(res, '用户名或密码错误');
          }
          s.jwxt = true;
          s.jwxtCaptcha = null;
          return _redirect(res, '/jwglxt/xtgl/index_initMenu.html');
        }
        return _html(res, _jwxtLoginPage);

      case '/jwglxt/xtgl/login_getPublicKey.html':
        return _json(res, {'modulus': _rsaModulusB64, 'exponent': _rsaExponentB64});

      case '/jwglxt/kaptcha':
        s.jwxtCaptcha = randomCaptchaCode();
        debugJwxtCaptcha = s.jwxtCaptcha;
        debugPrint('[mock] 教务验证码 = ${s.jwxtCaptcha}');
        return _png(res, renderCaptchaPng(s.jwxtCaptcha!));

      // 会话探活：未登录返回 302（客户端 checkSession → false）
      case '/jwglxt/xtgl/index_initMenu.html':
        if (!s.jwxt) return _redirect(res, '/jwglxt/xtgl/login_slogin.html');
        return _html(res, '<html><body><div id="mock">index_initMenu</div></body></html>');

      case '/jwglxt/cjcx/cjcx_cxXsgrcj.html':
        if (!s.jwxt) return _jwxtExpired(res);
        final xnm = form['xnm'] ?? '';
        final xqm = form['xqm'] ?? '';
        final items = _grades
            .where((g) => (xnm.isEmpty || g['xnm'] == xnm) && (xqm.isEmpty || g['xqm'] == xqm))
            .toList();
        return _json(res, {'items': items, 'totalResult': '${items.length}'});

      case '/jwglxt/kbcx/xskbcxMobile_cxXsKb.html':
        if (!s.jwxt) return _jwxtExpired(res);
        final zs = int.tryParse(form['zs'] ?? '') ?? 1;
        if (zs < 1 || zs > _mockWeekCount) {
          return _json(res, {'kbList': const [], 'rqazcList': const []});
        }
        return _json(res, {
          'kbList': [
            for (final c in _courses)
              if (zs >= (c['from'] as int) && zs <= (c['to'] as int))
                {
                  'kcmc': c['name'],
                  'cdmc': c['place'],
                  'xm': c['teacher'],
                  'kcb_id': c['code'],
                  'jxbmc': c['clazz'],
                  'xqj': '${(c['day'] as int) + 1}',
                  'jcs': c['slots'],
                },
          ],
          'rqazcList': _weekDates(zs),
          'xsxx': {'XNMC': '2026-2027学年', 'NJDM_ID': '2026'},
        });

      case '/jwglxt/kwgl/kscx_cxXsksxxIndex.html':
        if (!s.jwxt) return _jwxtExpired(res);
        return _json(res, {'items': _exams});
    }
    _text(res, 404, 'mock: 未实现的教务路径 $path', 'text/plain; charset=utf-8');
  }

  static const String _jwxtLoginPage = '''
<html><body>
<form id="loginForm" method="post" action="/jwglxt/xtgl/login_slogin.html">
  <input type="hidden" name="csrftoken" value="mock-csrf-token"/>
  <input type="text" name="yhm"/>
  <input type="password" name="mm"/>
  <input type="text" name="yzm"/>
  <img id="kaptchaImg" src="/jwglxt/kaptcha"/>
  <input type="submit" value="登录"/>
</form>
</body></html>''';

  void _tips(HttpResponse res, String msg) =>
      _html(res, '<html><body><div id="tips">$msg</div></body></html>');

  /// 教务登录失败页：默认 #tips 文案；测试用 debugJwxtLoginFailBody 换成没有可读文案的页面。
  void _jwxtLoginFail(HttpResponse res, String msg) {
    final body = debugJwxtLoginFailBody;
    if (body == null) return _tips(res, msg);
    _html(res, body);
  }

  /// 会话过期时业务接口的应答：真实正方有些版本不打回 302，而是直接给一张登录页 HTML
  /// （客户端若把它当成 JSON 解析就会失败，还容易误报成「这周没课」）。
  void _jwxtExpired(HttpResponse res) => _html(res, _jwxtLoginPage);

  /// 测试用：服务端偷偷把教务会话删掉（模拟正方会话超时），客户端并不知情。
  void debugForgetJwxtSession() {
    for (final s in _sessions.values) {
      s.jwxt = false;
    }
  }

  // ==================== 统一身份认证（CAS） ====================

  Future<void> _cas(
    HttpRequest req,
    HttpResponse res,
    _MockSession s,
    String path,
    Map<String, String> form,
  ) async {
    switch (path) {
      case '/authserver/login':
        if (req.method == 'POST') {
          final cap = (form['captchaResponse'] ?? '').toUpperCase();
          if (cap.isEmpty || cap != (s.authCaptcha ?? '').toUpperCase()) {
            return _casError(res, 'cpatchaError', '验证码错误');
          }
          if ((form['username'] ?? '') != studentId) {
            return _casError(res, 'usernameError', '用户名或密码错误');
          }
          if (!_wiseduPasswordOk(form['password'] ?? '', s.casSalt, password)) {
            return _casError(res, 'passwordError', '用户名或密码错误');
          }
          s.cas = true; // 统一认证会话（CASTGC）建立
          s.authCaptcha = null;
          return _redirect(res, _ticketUrl(s.casService));
        }
        s.casService = req.uri.queryParameters['service'] ?? s.casService;
        // 统一认证会话还有效时不渲染登录页，直接带票据 302 回业务系统（真实 CAS 的 SSO 行为）
        if (s.cas) return _redirect(res, _ticketUrl(s.casService));
        s.casExecution = 'e1s1-mock-${DateTime.now().microsecondsSinceEpoch}';
        s.casLt = 'LT-mock-${DateTime.now().microsecondsSinceEpoch}';
        s.casSalt = _randomSalt();
        return _html(res, _casLoginPage(s));

      case '/authserver/captcha.html':
        s.authCaptcha = randomCaptchaCode();
        debugAuthCaptcha = s.authCaptcha;
        debugPrint('[mock] 统一认证验证码 = ${s.authCaptcha}');
        return _png(res, renderCaptchaPng(s.authCaptcha!));
    }
    _text(res, 404, 'mock: 未实现的认证路径 $path', 'text/plain; charset=utf-8');
  }

  String _casLoginPage(_MockSession s) {
    final saltInput = debugFlipSaltAttribute
        ? '<input type="hidden" value="${s.casSalt}" id="pwdDefaultEncryptSalt"/>'
        : '<input type="hidden" id="pwdDefaultEncryptSalt" value="${s.casSalt}"/>';
    return '''
<html><body>
$casErrorSkeleton
<form id="casLoginForm" method="post" action="/authserver/login">
  <input type="hidden" name="execution" value="${s.casExecution}"/>
  <input type="hidden" name="_eventId" value="submit"/>
  <input type="hidden" name="lt" value="${s.casLt}"/>
  <input type="hidden" name="rmShown" value="1"/>
  <input type="hidden" name="dllt" value="userNamePasswordLogin"/>
  $saltInput
  <input type="text" id="username" name="username" placeholder="学号"/>
  <input type="password" id="password" name="password"/>
  <input type="text" id="captchaResponse" name="captchaResponse"/>
  <img id="captchaImg" src="/authserver/captcha.html"/>
  <button type="submit" class="auth_login_btn">登录</button>
</form>
</body></html>''';
  }

  /// SIT 真实 CAS 登录页的静态错误骨架（实测原文）：隐藏元素是给 JS 改文案用的，服务端判定结果
  /// 一律渲染在**可见的** `#msg`（实测：未填验证码 → 「请输入验证码」、验证码无效 → 「无效的验证码」），
  /// 且 `#msg` 在页面上排在骨架之后。客户端若抓隐藏元素，就会把「请输入密码」误报成账号密码错误——
  /// 这里保留同款骨架与顺序，让回归用例覆盖这条误报路径。
  static const String casErrorSkeleton = '''
<span id="usernameError" style="display:none;" class="auth_error">请输入用户名</span>
<span id="usernameSpecificError" style="display:none;" class="auth_error"></span>
<span id="passwordError" style="display:none;" class="auth_error">请输入密码</span>
<span id="cpatchaError" style="display:none;" class="auth_error">请输入验证码</span>''';

  /// 登录失败页：按 SIT 真实页面形态返回——静态骨架原样保留（含隐藏的 error 元素），
  /// 服务端判定结果渲染在可见的 `#msg`。客户端读的是可见元素，隐藏骨架不该被当成错误原因。
  void _casError(HttpResponse res, String elementId, String msg) => _html(
      res,
      '<html><body>$casErrorSkeleton'
      '<span id="msg" class="auth_error" style="top:-19px;">$msg</span>'
      '</body></html>');

  // ==================== 学工（第二课堂） ====================

  Future<void> _xg(
    HttpRequest req,
    HttpResponse res,
    _MockSession s,
    String path,
    Map<String, String> form,
  ) async {
    switch (path) {
      // 业务系统入口：没有业务会话就 302 去统一认证；带 ticket 回来则建立业务会话
      case '/zftal-xgxt-web/teacher/xtgl/index/check.zf':
        if ((req.uri.queryParameters['ticket'] ?? '').isNotEmpty && s.cas) s.xg = true;
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        return _html(res, '<html><body>xgHome ok</body></html>');

      case '/zftal-xgxt-web/teacher/xtgl/login/getCurrentUser.zf':
        return _json(res, s.xg
            ? {
                'code': 0,
                'msg': 'ok',
                'data': {'xh': studentId, 'xm': realName},
              }
            : {'code': 1, 'msg': '未登录'});

      case '/zftal-xgxt-web/xsrdtjcx/getAllXslbTjcx.zf':
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        return _json(res, {
          'code': 0,
          'tableHeader': _scoreHeader,
          'queryModel': {
            'items': [_scoreItem],
          },
        });

      case '/zftal-xgxt-web/hdgl/getHdgcHdList.zf':
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        return _json(res, {
          'code': 0,
          'data': {
            'resultList': [
              {
                'dlmc': '思想成长',
                'lblist': [
                  {'lbmc': '讲座报告', 'hdlist': [_activityItems['m001']]},
                  {'lbmc': '实践活动', 'hdlist': [_activityItems['m003']]},
                ],
              },
              {
                'dlmc': '社会实践',
                'lblist': [
                  {'lbmc': '志愿服务', 'hdlist': [_activityItems['m002']]},
                ],
              },
            ],
          },
        });

      case '/zftal-xgxt-web/hdgl/details.zf':
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        final a = _activityItems[req.uri.queryParameters['id'] ?? ''];
        if (a == null) return _json(res, {'code': 1, 'msg': '活动不存在'});
        return _json(res, {
          'code': 0,
          'data': {'id': a['id'], 'hdmc': a['hdmc'], 'hdms': a['hdms']},
        });
    }
    _text(res, 404, 'mock: 未实现的学工路径 $path', 'text/plain; charset=utf-8');
  }

  String _casLoginUrl(String servicePath) =>
      '$baseUrl/authserver/login?service=${Uri.encodeComponent('$baseUrl$servicePath')}';

  /// 统一认证回业务系统的跳转：真实 CAS 一定带 ticket（业务系统据此建会话）。
  String _ticketUrl(String service) {
    final target =
        service.isEmpty ? '$baseUrl/zftal-xgxt-web/teacher/xtgl/index/check.zf' : service;
    final sep = target.contains('?') ? '&' : '?';
    return '$target${sep}ticket=ST-mock-${DateTime.now().microsecondsSinceEpoch}';
  }

  /// 测试用：只丢业务会话、保留统一认证会话（模拟 CASTGC 还有效但学工 Cookie 过期）。
  /// 旧实现的坑正是这里：authserver 会把登录页 302 回业务系统，拿到的是业务页而非登录页。
  void debugForgetXgSession() {
    for (final s in _sessions.values) {
      s.xg = false;
    }
  }

  // ==================== 校付宝 ====================

  Future<void> _epay(
    HttpRequest req,
    HttpResponse res,
    _MockSession s,
    String path,
    Map<String, dynamic> json,
  ) async {
    if (path == '/openservice/epeortalAuth/login') {
      if ('${json['custname']}' != realName || '${json['stuempno']}' != studentId) {
        return _json(res, {'retcode': '-1', 'retmsg': '姓名或学号有误'});
      }
      String pwd;
      try {
        pwd = sm4Decrypt('${json['pwd']}');
      } catch (_) {
        return _json(res, {'retcode': '-2', 'retmsg': '支付密码解密失败'});
      }
      if (pwd != payPassword) return _json(res, {'retcode': '-1', 'retmsg': '支付密码错误'});
      s.epayToken = 'mock-token-${DateTime.now().microsecondsSinceEpoch}';
      return _json(res, {
        'retcode': '0',
        'retmsg': '登录成功',
        'data': {'token': s.epayToken},
      });
    }

    // 其余 openservice 接口都要 Bearer token；过期回 403（客户端会重登续期后重试）
    final auth = req.headers.value('sw-Authorization') ?? '';
    final token = auth.startsWith('Bearer ') ? auth.substring(7) : '';
    if (s.epayToken == null || token != s.epayToken) {
      return _json(res, {'retcode': '-3', 'retmsg': '登录已过期'}, status: 403);
    }

    switch (path) {
      case '/openservice/miniprogram/wxlayout':
        return _json(res, {
          'retcode': '0',
          'data': {
            'layout': {
              'balancePart': {
                'content': [
                  {'number': s.cardBalance.toStringAsFixed(2)},
                ],
              },
            },
          },
        });

      case '/openservice/miniprogram/queryroominfo':
        final buildid = '${json['buildid']}';
        final roomid = '${json['roomid']}';
        if (buildid != '${_dormBuilding + 1}' || roomid != '$_dormRoom') {
          return _json(res, {
            'retcode': '-1',
            'retmsg': '该寝室不存在（mock 只登记 $dorm）',
          });
        }
        return _json(res, {
          'retcode': '0',
          'data': {
            'restElecDegree': s.eleBalance.toStringAsFixed(2),
            'roomName': draftDormName,
          },
        });

      case '/openservice/miniprogram/buyelectrityinit':
        s.pendingBillno = 'MOCK${DateTime.now().millisecondsSinceEpoch}';
        s.pendingAmount = (json['amount'] as num?)?.toDouble() ?? 0;
        return _json(res, {
          'retcode': '0',
          'data': {'billno': s.pendingBillno},
        });

      case '/openservice/miniprogram/balancepay':
        if (s.pendingBillno == null || '${json['billno']}' != s.pendingBillno) {
          return _json(res, {'retcode': '-1', 'retmsg': '订单号不匹配'});
        }
        final amount = s.pendingAmount;
        s.pendingBillno = null;
        s.pendingAmount = 0;
        s.eleBalance += amount / 100;
        s.cardBalance -= amount / 100;
        return _json(res, {
          'retcode': '0',
          'data': {
            'balance': (s.cardBalance * 100).round(), // 客户端按「分」解读
            'retmsg': '充值成功（mock）',
          },
        });

      case '/openservice/miniprogram/offline':
        return _json(res, {
          'retcode': '0',
          'data': {
            'qrcode': 'MOCK|$studentId|${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
          },
        });
    }
    _text(res, 404, 'mock: 未实现的校付宝路径 $path', 'text/plain; charset=utf-8');
  }

  // ==================== 响应工具 ====================

  void _text(HttpResponse res, int status, String body, String contentType) {
    res.statusCode = status;
    res.headers.contentType = ContentType.parse(contentType);
    res.write(body);
    res.close();
  }

  void _html(HttpResponse res, String html) =>
      _text(res, 200, html, 'text/html; charset=utf-8');

  void _json(HttpResponse res, Object body, {int status = 200}) {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    res.close();
  }

  void _png(HttpResponse res, List<int> bytes) {
    res.headers.contentType = ContentType('image', 'png');
    res.add(bytes);
    res.close();
  }

  void _redirect(HttpResponse res, String location) {
    res.statusCode = HttpStatus.found; // 302：客户端据此判定「登录失效 / 登录成功」
    res.headers.add('Location', location);
    res.close();
  }

  // ==================== 加密校验 ====================

  /// 正方密码：RSA/PKCS#1 v1.5 解密（n/d 模幂 + 去填充），解不出原文返回空串。
  /// 填充块是 0x00 || 块类型 || 非零填充 || 0x00 || 明文：加密（块类型 2）与签名（块类型 1）
  /// 都只需「跳过第一段非零字节」；大数转换会吃掉开头那个 0x00，故前导零可有可无。
  String _rsaDecrypt(String cipherB64) {
    try {
      final m = _bigIntFromBytes(base64Decode(cipherB64)).modPow(_rsaPrivate, _rsaModulus);
      final bytes = _bytesFromBigInt(m);
      if (bytes.length < 11) return '';
      var i = bytes[0] == 0 ? 1 : 0;
      final type = bytes[i];
      if (type != 1 && type != 2) return '';
      i++;
      while (i < bytes.length && bytes[i] != 0) {
        i++;
      }
      if (i >= bytes.length) return '';
      return utf8.decode(bytes.sublist(i + 1), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  /// 统一认证密码校验：AES-128-CBC，key = salt 前 16 字节。
  /// 明文 = 64 字符随机前缀 + 真实密码；IV 由客户端随机生成且不随密文传输，
  /// 而 IV 未知只会毁掉第一个分组——第一个分组正属于被丢弃的 64 字符前缀，
  /// 所以真实 authserver 也是这么解出密码的：解出来看尾部是不是那个密码。
  bool _wiseduPasswordOk(String cipherB64, String salt, String expected) {
    try {
      final raw = base64Decode(cipherB64);
      if (raw.length <= 16 || raw.length % 16 != 0) return false;
      final text = utf8.decode(
        aesCbcPkcs7Decrypt(raw, _key16(salt), List<int>.filled(16, 0)),
        allowMalformed: true,
      );
      return text.endsWith(expected);
    } catch (_) {
      return false;
    }
  }

  /// salt 前 16 字节（不足补 0），与 App 的 crypto.dart 一致。
  static List<int> _key16(String salt) {
    final b = utf8.encode(salt.trim());
    if (b.length >= 16) return b.sublist(0, 16);
    return [...b, ...List<int>.filled(16 - b.length, 0)];
  }

  static String _randomSalt() {
    const chars = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';
    final r = Random();
    return List<String>.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static BigInt _bigIntFromBytes(List<int> bytes) {
    var v = BigInt.zero;
    for (final b in bytes) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }

  static List<int> _bytesFromBigInt(BigInt v) {
    final out = <int>[];
    var x = v;
    final mask = BigInt.from(0xFF);
    while (x > BigInt.zero) {
      out.insert(0, (x & mask).toInt());
      x = x >> 8;
    }
    return out;
  }

  // ==================== 假数据 ====================

  static const int _mockWeekCount = 20;
  static final DateTime _semesterStart = DateTime(2026, 9, 7); // 第 1 周周一

  // 寝室：24 号楼 1016（接口约定 buildid = 楼号 + 1）
  static const int _dormBuilding = 24;
  static const int _dormRoom = 1016;
  static const String draftDormName = '24号楼1016';

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static List<Map<String, String>> _weekDates(int zs) {
    final monday = _semesterStart.add(Duration(days: (zs - 1) * 7));
    return [
      for (var i = 0; i < 7; i++)
        {'xqj': '${i + 1}', 'rq': _fmtDate(monday.add(Duration(days: i)))},
    ];
  }

  static const List<Map<String, Object>> _courses = [
    {'name': '高等数学(下)', 'place': '二教E101', 'teacher': '王建国', 'code': 'MA1102',
      'clazz': '数学2501-01', 'day': 0, 'slots': '1-2', 'from': 1, 'to': 17},
    {'name': '大学英语(二)', 'place': '外教楼305', 'teacher': '李梅', 'code': 'EN1102',
      'clazz': '英语2503-02', 'day': 0, 'slots': '3', 'from': 1, 'to': 17},
    {'name': '数据结构', 'place': '一教A203', 'teacher': '陈强', 'code': 'CS2101',
      'clazz': '计科2501-01', 'day': 1, 'slots': '1-2', 'from': 1, 'to': 16},
    {'name': '数据结构实验', 'place': '实验楼506', 'teacher': '陈强', 'code': 'CS2102',
      'clazz': '计科2501-02', 'day': 3, 'slots': '4-5', 'from': 2, 'to': 16},
    {'name': '大学物理(二)', 'place': '二教B110', 'teacher': '赵芳', 'code': 'PH1201',
      'clazz': '物理2502-01', 'day': 2, 'slots': '3', 'from': 1, 'to': 17},
    {'name': '思想道德与法治', 'place': '一教C108', 'teacher': '孙丽', 'code': 'PY1101',
      'clazz': '思政2501-05', 'day': 4, 'slots': '1-2', 'from': 1, 'to': 15},
    {'name': '大学体育(二)', 'place': '体育馆', 'teacher': '周斌', 'code': 'PE1102',
      'clazz': '体育 Club-08', 'day': 4, 'slots': '4', 'from': 1, 'to': 16},
    {'name': '线性代数', 'place': '二教E201', 'teacher': '吴敏', 'code': 'MA1201',
      'clazz': '数学2502-03', 'day': 2, 'slots': '4-5', 'from': 1, 'to': 17},
    {'name': '程序设计实践', 'place': '实验楼402', 'teacher': '郑浩', 'code': 'CS1105',
      'clazz': '计科2501-01', 'day': 1, 'slots': '4-5', 'from': 3, 'to': 14},
  ];

  static const List<Map<String, String>> _exams = [
    {'kcmc': '高等数学(下)', 'ksmc': '期末考试', 'kssj': '2027-01-10(08:00-09:40)',
      'cdmc': '二教E101', 'zwh': '12', 'ksfs': '笔试'},
    {'kcmc': '数据结构', 'ksmc': '期末考试', 'kssj': '2027-01-12(10:00-11:40)',
      'cdmc': '一教A203', 'zwh': '05', 'ksfs': '笔试'},
    {'kcmc': '大学英语(二)', 'ksmc': '期末考试', 'kssj': '2027-01-14(14:00-15:40)',
      'cdmc': '外语楼305', 'zwh': '23', 'ksfs': '机考'},
  ];

  static Map<String, Object?> _grade(String kcmc, String cj, String xf, String lb, String fs,
          {String xnm = '2026',
          String xqm = '3',
          String xnmmc = '2026-2027学年',
          String xqmmc = '第一学期'}) =>
      {
        'kcmc': kcmc, 'cj': cj, 'xf': xf, 'jd': '', 'xfjd': '',
        'kclbmc': lb, 'kcxzmc': '主修', 'khfsmc': fs,
        'xqmmc': xqmmc, 'xnmmc': xnmmc, 'sfxwkc': '否', 'xnm': xnm, 'xqm': xqm,
      };

  /// 两个学期的成绩：xnm/xqm 传空时返回全部，客户端据此生成学期列表。
  static final List<Map<String, Object?>> _grades = [
    _grade('高等数学(上)', '92', '4.0', '必修', '考试'),
    _grade('大学英语(一)', '88', '3.0', '必修', '考试'),
    _grade('程序设计基础', '95', '4.0', '必修', '考试'),
    _grade('思想道德与法治', '90', '2.5', '必修', '考查'),
    _grade('线性代数', '85', '2.0', '必修', '考试',
        xnm: '2025', xqm: '3', xnmmc: '2025-2026学年'),
    _grade('中国近现代史纲要', '92', '2.0', '必修', '考查',
        xnm: '2025', xqm: '3', xnmmc: '2025-2026学年'),
  ];

  static const List<Map<String, String>> _scoreHeader = [
    {'fieldCode': 'xh', 'fieldName': '学号', 'fieldTh': '基本信息'},
    {'fieldCode': 'xm', 'fieldName': '姓名', 'fieldTh': '基本信息'},
    {'fieldCode': 'nj', 'fieldName': '年级', 'fieldTh': '基本信息'},
    {'fieldCode': 'bmmc', 'fieldName': '院系', 'fieldTh': '基本信息'},
    {'fieldCode': 'zymc', 'fieldName': '专业', 'fieldTh': '基本信息'},
    {'fieldCode': 'bjmc', 'fieldName': '班级', 'fieldTh': '基本信息'},
    {'fieldCode': 'zxs', 'fieldName': '总学时', 'fieldTh': '统计'},
    {'fieldCode': 'sjxf', 'fieldName': '实践学分', 'fieldTh': '统计'},
    {'fieldCode': 'dlxs_dy', 'fieldName': '德育小计', 'fieldTh': '德育'},
    {'fieldCode': 'rdxs_dy_jzbg', 'fieldName': '讲座报告', 'fieldTh': '德育'},
    {'fieldCode': 'rdxs_dy_ztjy', 'fieldName': '主题教育', 'fieldTh': '德育'},
    {'fieldCode': 'rdxs_dy_zygy', 'fieldName': '志愿公益', 'fieldTh': '德育'},
    {'fieldCode': 'dlxs_ly', 'fieldName': '劳育小计', 'fieldTh': '劳育'},
    {'fieldCode': 'rdxs_ly_ldkt', 'fieldName': '劳动课堂', 'fieldTh': '劳育'},
    {'fieldCode': 'rdxs_ly_shsj', 'fieldName': '社会实践', 'fieldTh': '劳育'},
    {'fieldCode': 'dlxs_my', 'fieldName': '美育小计', 'fieldTh': '美育'},
    {'fieldCode': 'dlxs_jkjy', 'fieldName': '健康教育小计', 'fieldTh': '健康教育'},
  ];

  static const Map<String, Object?> _scoreItem = {
    'xh': studentId, 'xm': realName, 'nj': '2026',
    'bmmc': '计算机学院', 'zymc': '计算机科学与技术', 'bjmc': '计科2501',
    'zxs': '8.0', 'sjxf': '5.5',
    'dlxs_dy': '2.0', 'rdxs_dy_jzbg': '0.8', 'rdxs_dy_ztjy': '0.4', 'rdxs_dy_zygy': '0.8',
    'dlxs_ly': '1.5', 'rdxs_ly_ldkt': '0.5', 'rdxs_ly_shsj': '1.0',
    'dlxs_my': '0.5', 'dlxs_jkjy': '0.5',
  };

  static const Map<String, Map<String, Object?>> _activityItems = {
    'm001': {
      'id': 'm001',
      'hdmc': 'AI 赋能学习效率提升讲座',
      'zbfmc': '校学生会',
      'hdbmkssj': '2026-09-25 10:00:00',
      'hdbmjzsj': '2026-10-08 22:00:00',
      'hdkssj': '2026-10-10 14:00:00',
      'hdjssj': '2026-10-10 16:00:00',
      'hdms': '邀请企业 AI 工程师分享大模型在学习场景的实践应用，参与可获思想成长模块 0.2 分。\n'
          '人数：200 人\n报名请加 QQ 群 765432198，联系人：李同学 13800000000',
    },
    'm002': {
      'id': 'm002',
      'hdmc': '秋季校园马拉松志愿者',
      'zbfmc': '校团委',
      'hdbmkssj': '2026-10-05 12:00:00',
      'hdbmjzsj': '2026-10-12 18:00:00',
      'hdkssj': '2026-10-18 07:00:00',
      'hdjssj': '2026-10-18 13:00:00',
      'hdms': '负责奉贤赛道补给站物资发放与观众引导，计社会实践 0.5 分。\n'
          '名额：80 人\n报名方式：扫码填写问卷，联系人：王老师',
    },
    'm003': {
      'id': 'm003',
      'hdmc': '实验室开放日参观',
      'zbfmc': '计算机学院',
      'hdbmkssj': '2026-09-01 09:00:00',
      'hdbmjzsj': '2026-09-02 17:00:00',
      'hdkssj': '2026-09-20 13:30:00',
      'hdjssj': '2026-09-20 17:00:00',
      'hdms': '参观徐汇人工智能实验室与机器人实验室，了解本科生科研训练项目报名方式。',
    },
  };

  // ==================== 模拟服务的 RSA 密钥 ====================
  // 由 tool/gen_mock_rsa.dart 生成（2048 位），只用于本机模拟服务。

  static const String _rsaModulusB64 =
      'rJOjpMlVG5TgBhfpBg+j63HMw2S1vHBC6B5jcMEOYRfLJGtPo7QK07Z53BW/ZPQcASOJvzRAhzz8SW/Qn2ncKiyUNVA7zXrWXWK3lVN77uLj8bcIPJg3Q3Qra4dXPqYkY2OT4eIYompS51WpNdJV7RjD25ul9LO6yftfaR3gp2YrBxyWtzfICAuB4mWImOrGnJz49g6S41RvvvhEIIJ/A1fYwjrMhZHB6LYPkFsqSvW4qoUJKSw8iA4HI55MSnPIFREn72g9T+QRI3cntnJVKG9ca4T2nBXfWQ0nkBj1uEVE66g+goxaQuDiMX0kCQWQbR8ywv06s1yXYewLTZK0Xw==';
  static const String _rsaExponentB64 = 'AQAB';
  static const String _rsaPrivateB64 =
      'pR6J15QvEznJcusTsRHr4805fsZwQEElMxRITszYpjtuyYTHaTlNlq2kQNiqDLynwssu87vZ9ct7FAShFrXhypRmpfADmCHs0uMuBfkfvjxmnpJilh+J2Mdg9/xBlJbAgDv5dYmvyk5yzhae1PlP74/fbdKp4czJbpJOArRsi5zZNBIEYW12ET0iwTWp0kJfEEhrXos3mttohbaTiLWq1E6UTnb3O5faFTnf8dIb1h4rgDqyb8LlT7pc72UseA/bTFqoEamLxiKaBRGSiSf77J8LW8KAv7kt8vwLyw1jeIupqDQXSenoMWlkfe2ED+TvP7Hg8u0Vw5RuObt0ovMFEQ==';

  static final BigInt _rsaModulus = _bigIntFromBytes(base64Decode(_rsaModulusB64));
  static final BigInt _rsaPrivate = _bigIntFromBytes(base64Decode(_rsaPrivateB64));
}

class _MockSession {
  bool jwxt = false; // 教务已登录
  bool cas = false; // 统一认证会话（CASTGC）已建立
  bool xg = false; // 学工业务会话（靠 CAS 回跳带的 ticket 建立）
  String? jwxtCaptcha;
  String? authCaptcha;
  String casService = '';
  String casExecution = '';
  String casLt = '';
  String casSalt = '';
  String? epayToken;
  double eleBalance = 23.45; // 电费余额（元）
  double cardBalance = 56.70; // 校园卡余额（元）
  String? pendingBillno;
  double pendingAmount = 0; // 分
}
