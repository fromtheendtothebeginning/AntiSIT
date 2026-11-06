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
  static const String grade = '2026';

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

  /// 测试用：替换教务成绩单（造多页数据验证分页）。null = 内置样例成绩。
  List<Map<String, Object?>>? debugGrades;

  /// 测试用：替换学业情况首页 HTML（造「页面改版 / 学校报错 / 缺统计」等变体）。
  /// null = 内置样例页面。
  String? debugAcademicIndexHtml;

  /// 测试用：替换学业情况各节点的课程明细（key = xfyqjd_id）。null = 内置样例。
  Map<String, List<Map<String, Object?>>>? debugAcademicCourses;

  /// 测试用：让节点课程明细接口返回这段非 JSON 内容（模拟接口改版被改回 HTML）。
  String? debugAcademicCoursesBody;

  /// 测试用：替换「非课程信息」节点明细（jdkcsx != 1，key = xfyqjd_id）。
  Map<String, List<Map<String, Object?>>>? debugAcademicNonCourses;

  /// 测试用：最近一次节点课程明细请求的表单（验证首页隐藏域是否原样回传）。
  Map<String, String>? debugLastAcademicForm;

  /// 测试用：学业情况明细请求的流水（`文件名:xfyqjd_id`），验证按 jdkcsx 选对了接口。
  final List<String> debugAcademicRequestLog = <String>[];

  /// 测试用：选课前 N 次返回「名额已满」，之后成功（验证抢课自动重试）。
  int debugSelectFailures = 0;

  /// 测试用：最近一次选课提交的表单体（验证 jxb_ids / kch_id / 控制参数）。
  Map<String, String>? debugLastSelectForm;

  /// 测试用：清空本地模拟的已选课程与抢课状态。
  void debugResetCourseSelection() {
    debugSelectFailures = 0;
    debugLastSelectForm = null;
    _selectedCourses.clear();
  }

  final List<Map<String, String>> _selectedCourses = <Map<String, String>>[];

  /// 测试用：最近一次收到的报名提交体（验证预填回传 / 自述字段透传 / 附件字段剔除）。
  Map<String, String>? debugLastSignupForm;

  /// 测试用：模拟新生账号在正方侧没有可用密码（浏览器里只能点统一身份认证登入），
  /// 账号密码表单永远回「用户名或密码错误」；统一认证 CAS 仍可用同一密码登录。
  bool debugJwxtPasswordLoginRejected = false;

  /// 测试用：登录页不放统一认证入口，且 SSO 兜底路径 404（学校未开 SSO）。
  bool debugJwxtNoSsoEntry = false;

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
      if (path.startsWith('/epeortal')) return _html(res, '<html><body>校园卡 H5（mock）</body></html>');
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
          if (debugJwxtPasswordLoginRejected || _rsaDecrypt(form['mm'] ?? '') != password) {
            return _jwxtLoginFail(res, '用户名或密码错误');
          }
          s.jwxt = true;
          s.jwxtCaptcha = null;
          return _redirect(res, '/jwglxt/xtgl/index_initMenu.html');
        }
        return _html(res, _loginPageHtml);

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

      // 统一认证入口：未带票据 → 302 去 authserver；带 ticket 回来 → 建立教务会话
      case '/jwglxt/xtgl/login_ssologin.html':
        if (debugJwxtNoSsoEntry) {
          return _text(res, 404, 'mock: 未开启统一身份认证', 'text/plain; charset=utf-8');
        }
        if ((req.uri.queryParameters['ticket'] ?? '').isNotEmpty && s.cas) {
          s.jwxt = true;
          return _redirect(res, '/jwglxt/xtgl/index_initMenu.html');
        }
        final service = '$baseUrl/jwglxt/xtgl/login_ssologin.html';
        return _redirect(
            res, '$baseUrl/authserver/login?service=${Uri.encodeComponent(service)}');

      case '/jwglxt/cjcx/cjcx_cxXsgrcj.html':
        if (!s.jwxt) return _jwxtExpired(res);
        final xnm = form['xnm'] ?? '';
        final xqm = form['xqm'] ?? '';
        final all = (debugGrades ?? _grades)
            .where((g) => (xnm.isEmpty || g['xnm'] == xnm) && (xqm.isEmpty || g['xqm'] == xqm))
            .toList();
        // 真实正方按 queryModel.showCount/currentPage 分页，totalResult 给总条数：
        // 客户端只取第 1 页就会漏掉后面的学期，这里必须照做才能测出这种漏。
        final size = int.tryParse(form['queryModel.showCount'] ?? '') ?? 15;
        final page = int.tryParse(form['queryModel.currentPage'] ?? '') ?? 1;
        final from = (page - 1) * size;
        final items = from >= all.length ? const [] : all.skip(from).take(size).toList();
        return _json(res, {'items': items, 'totalResult': '${all.length}'});

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

      // 学业情况：首页由服务端渲染 HTML（整体统计 + 各节点学分要求 + showKc 占位），
      // 某个节点的课程再由前端 POST xfyqjd_id 换 JSON 数组——照真实协议分两步。
      case '/jwglxt/xsxy/xsxyqk_cxXsxyqkIndex.html':
        if (!s.jwxt) return _jwxtExpired(res);
        return _html(res, debugAcademicIndexHtml ?? _academicIndexPage);

      case '/jwglxt/xsxy/xsxyqk_cxJxzxjhxfyqKcxx.html':
        if (!s.jwxt) return _jwxtExpired(res);
        debugLastAcademicForm = Map<String, String>.from(form);
        debugAcademicRequestLog.add('plan:${form['xfyqjd_id'] ?? ''}');
        final rawBody = debugAcademicCoursesBody;
        if (rawBody != null) {
          return _text(res, 200, rawBody, 'text/html; charset=utf-8');
        }
        final id = form['xfyqjd_id'] ?? '';
        // debug 覆盖按节点合并（只覆盖指定 id，其余仍用内置样例），方便单点造变体。
        final override = debugAcademicCourses;
        final data = (override != null && override.containsKey(id))
            ? override[id]!
            : _academicCourses[id] ?? const [];
        return _json(res, data);

      // 非课程信息节点（页面 loadKc() 里 jdkcsx != '1' 的分支）：
      // 通识类 / 实践环节等的明细在这里，接口与教学计划分开。
      case '/jwglxt/xsxy/xsxyqk_cxJxzxjhxfyqFKcxx.html':
        if (!s.jwxt) return _jwxtExpired(res);
        final nonCourseId = form['xfyqjd_id'] ?? '';
        debugAcademicRequestLog.add('noncourse:$nonCourseId');
        return _json(
          res,
          (debugAcademicNonCourses ?? _academicNonCourses)[nonCourseId] ?? const [],
        );

      // ===== 选课（正方 9.0 zzxk）=====
      // 首页：选课轮次参数藏在隐藏域里，类别由 queryCourse(...) 声明。
      case '/jwglxt/xsxk/zzxkyzb_cxZzxkYzbIndex.html':
        if (!s.jwxt) return _jwxtExpired(res);
        return _html(res, _courseIndexPage);

      // 展示页：返回该类别最新的 xkkz_id / xkkz_xh（两者独立，不能互相推导）。
      case '/jwglxt/xsxk/zzxkyzb_cxZzxkYzbDisplay.html':
        if (!s.jwxt) return _jwxtExpired(res);
        final displayCategory = form['kklxdm'] ?? '1';
        final displayControl = displayCategory == '2'
            ? const ['KZ2', 'XH2', '通识选课']
            : const ['KZ1', 'XH1', '主修选课'];
        return _html(res, '''
<html><body>
<input type="hidden" name="xkkz_id" value="${displayControl[0]}"/>
<input type="hidden" name="xkkz_xh" value="${displayControl[1]}"/>
<input type="hidden" name="kklxmc" value="${displayControl[2]}"/>
</body></html>''');

      // 课程列表：kspage/jspage 是 1 基记录号（不是页码），filter_list[0] 是关键词。
      case '/jwglxt/xsxk/zzxkyzb_cxZzxkYzbPartDisplay.html':
        if (!s.jwxt) return _jwxtExpired(res);
        final listCategory = form['kklxdm'] ?? '1';
        final keyword = (form['filter_list[0]'] ?? '').trim();
        final offers = <Map<String, Object?>>[
          if (listCategory == '1') ...[
            {
              'kch_id': 'K001',
              'kcmc': '高等数学',
              'jsxm': '李老师',
              'sksj': '周一 1-2节',
              'jxdd': 'A101',
              'xf': '4.0',
              'jxbrl': '60',
              'yxzrs': '60',
            },
            {
              'kch_id': 'K002',
              'kcmc': '大学英语',
              'jsxm': '王老师',
              'sksj': '周三 3-4节',
              'jxdd': 'B202',
              'xf': '3.0',
              'jxbrl': '40',
              'yxzrs': '12',
            },
          ] else if (listCategory == '2') ...[
            {
              'kch_id': 'K003',
              'kcmc': '中国近现代史纲要',
              'jsxm': '赵老师',
              'sksj': '周五 5-6节',
              'jxdd': 'C303',
              'xf': '2.0',
              'jxbrl': '80',
              'yxzrs': '3',
            },
          ],
        ]
            .where((c) =>
                keyword.isEmpty || '${c['kcmc']}'.contains(keyword))
            .toList();
        final from = ((int.tryParse(form['kspage'] ?? '') ?? 1) - 1).clamp(0, offers.length);
        final to = (int.tryParse(form['jspage'] ?? '') ?? offers.length)
            .clamp(from, offers.length);
        return _json(res, {'tmpList': offers.sublist(from, to)});

      // 教学班：jxb_id 与提交用的 do_jxb_id 可以不同，客户端应优先用后者。
      case '/jwglxt/xsxk/zzxkyzbjk_cxJxbWithKchZzxkYzb.html':
        if (!s.jwxt) return _jwxtExpired(res);
        final sectionCourse = form['kch_id'] ?? '';
        final sections = <Map<String, Object?>>[
          if (sectionCourse == 'K001') ...[
            {
              'jxb_id': 'JXB1',
              'do_jxb_id': 'TOKEN1',
              'jxbmc': '高等数学01班',
              'jsxm': '李老师',
              'sksj': '周一 1-2节',
              'jxdd': 'A101',
              'jxbrl': '60',
              'yxzrs': '60',
            },
            {
              'jxb_id': 'JXB2',
              'do_jxb_id': 'TOKEN2',
              'jxbmc': '高等数学02班',
              'jsxm': '李老师',
              'sksj': '周二 3-4节',
              'jxdd': 'A102',
              'jxbrl': '60',
              'yxzrs': '59',
            },
          ] else if (sectionCourse == 'K002') ...[
            {
              'jxb_id': 'JXB3',
              'do_jxb_id': 'TOKEN3',
              'jxbmc': '大学英语01班',
              'jsxm': '王老师',
              'sksj': '周三 3-4节',
              'jxdd': 'B202',
              'jxbrl': '40',
              'yxzrs': '12',
            },
          ] else if (sectionCourse == 'K003') ...[
            {
              'jxb_id': 'JXB4',
              'do_jxb_id': 'TOKEN4',
              'jxbmc': '近现代史01班',
              'jsxm': '赵老师',
              'sksj': '周五 5-6节',
              'jxdd': 'C303',
              'jxbrl': '80',
              'yxzrs': '3',
            },
          ],
        ];
        return _json(res, {'tmpList': sections});

      // 选课提交：正常返回纯文本 1；名额满返回 flag=-1 + "已报人数,jxb_id,剩余,"。
      case '/jwglxt/xsxk/zzxkyzbjk_xkBcZyZzxkYzb.html':
        if (!s.jwxt) return _jwxtExpired(res);
        debugLastSelectForm = Map<String, String>.from(form);
        if (debugSelectFailures > 0) {
          debugSelectFailures--;
          return _json(res, {'flag': '-1', 'msg': '60,TOKEN2,0,'});
        }
        final jxb = form['jxb_ids'] ?? '';
        if (_selectedCourses.any((c) => c['jxb_id'] == jxb)) {
          return _json(res, {'flag': '-1', 'msg': '已选该教学班'});
        }
        _selectedCourses.add({
          'jxb_id': jxb,
          'do_jxb_id': jxb,
          'kch_id': form['kch_id'] ?? '',
          'kcmc': form['kcmc'] ?? '',
        });
        return _text(res, 200, '1', 'text/plain; charset=utf-8');

      case '/jwglxt/xsxk/zzxkyzb_cxZzxkYzbChoosedDisplay.html':
        if (!s.jwxt) return _jwxtExpired(res);
        return _json(res, {'tmpList': _selectedCourses});
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
<a id="authLogin" href="/jwglxt/xtgl/login_ssologin.html">统一身份认证登录</a>
</body></html>''';

  /// 未开启统一身份认证时，登录页上去掉那个按钮（客户端应回落到「账号密码登录失败」）。
  static const String _jwxtLoginPageNoSso = '''
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

  String get _loginPageHtml => debugJwxtNoSsoEntry ? _jwxtLoginPageNoSso : _jwxtLoginPage;

  /// 选课首页：隐藏域给出学期与控制参数，queryCourse(...) 给出可选类别。
  /// 两个类别的 xkkz_id / xkkz_xh 故意互不相同，用来测「两者独立、不能互相推导」。
  static const String _courseIndexPage = '''
<html><body>
<input type="hidden" name="xkxnm" value="2026"/>
<input type="hidden" name="xkxqm" value="12"/>
<input type="hidden" name="firstXkkzId" value="KZ1"/>
<input type="hidden" name="firstXkkzXh" value="XH1"/>
<script>
function queryCourse(kklxdm, xkkzId, njdmId, zyhId, xkkzXh) {}
queryCourse('1', 'KZ1', '2025', 'ZY1', 'XH1');
queryCourse('2', 'KZ2', '2025', 'ZY1', 'XH2');
</script>
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
  void _jwxtExpired(HttpResponse res) => _html(res, _loginPageHtml);

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

      // 我的报名：all=0 只回本人已报名（bm=1）；all=1 是全部活动。
      case '/zftal-xgxt-web/hdgl/list.zf':
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        final signedOnly = (form['all'] ?? '1') == '0';
        final items = [
          {
            'id': 'm001', 'hdmc': 'AI 赋能学习效率提升讲座',
            'dldm': '01', 'dlmc': '思想成长', 'lbdm': '0101', 'lbmc': '讲座报告',
            'hdkssj': '2026-10-10 14:00:00', 'hdjssj': '2026-10-10 16:00:00',
            'hddd': '线下', 'hdbmzt': '5', 'bm': signedOnly ? 1 : 0,
          },
          {
            'id': 'm002', 'hdmc': '秋季校园马拉松志愿者',
            'dldm': '02', 'dlmc': '劳育', 'lbdm': '0201', 'lbmc': '志愿公益',
            'hdkssj': '2026-10-18 07:00:00', 'hdjssj': '2026-10-18 13:00:00',
            'hddd': '线下', 'hdbmzt': '6', 'bm': signedOnly ? 1 : 0,
          },
          if (!signedOnly)
            {
              'id': 'm003', 'hdmc': '实验室开放日参观',
              'dldm': '03', 'dlmc': '美育', 'lbdm': '0301', 'lbmc': '校园文化活动',
              'hdkssj': '2026-09-20 13:30:00', 'hdjssj': '2026-09-20 17:00:00',
              'hddd': '线下', 'hdbmzt': '6', 'bm': 0,
            },
        ];
        return _json(res, {
          'code': 0,
          'msg': '操作成功',
          'data': {'items': items, 'totalCount': items.length, 'pageNo': 0, 'pageSize': 15},
        });

      // 第二课堂加分明细：每条 = 一次活动参与记录 + 学分。
      case '/zftal-xgxt-web/bizFlow/result/group/list.zf':
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        return _json(res, {
          'code': 0,
          'msg': '操作成功',
          'data': {
            'bizName': '学生活动申请',
            'formCode': 'hdsq',
            'formName': '学生活动申请',
            'totalCount': 2,
            'rows': [
              {
                'INSTANCE_ID': 'inst-1',
                'hdmc': 'AI 赋能学习效率提升讲座',
                'dldm': '德育', 'lbdm': '讲座报告',
                'hdxf': '0.20', 'jcxsxf': '0.2', 'zzxsxf': '0.2',
                'flowstatusmc': '通过', 'FLOWSTATUS': 'finish',
                'hdkssj': '2026-10-10 14:00:00', 'hdjssj': '2026-10-10 16:00:00',
                'CREATE_TIME': '2026-10-11 09:00:00',
              },
              {
                'INSTANCE_ID': 'inst-2',
                'hdmc': '秋季校园马拉松志愿者',
                'dldm': '劳育', 'lbdm': '志愿公益',
                'hdxf': '0.50', 'jcxsxf': '0.5', 'zzxsxf': '0.5',
                'flowstatusmc': '通过', 'FLOWSTATUS': 'finish',
                'hdkssj': '2026-10-18 07:00:00', 'hdjssj': '2026-10-18 13:00:00',
                'CREATE_TIME': '2026-10-19 10:00:00',
              },
            ],
          },
        });

      case '/zftal-xgxt-web/hdgl/details.zf':
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        final id = req.uri.queryParameters['id'] ?? '';
        final a = _activityItems[id];
        if (a == null) return _json(res, {'code': 1, 'msg': '活动不存在'});
        return _json(res, {
          'code': 0,
          'data': {
            'id': a['id'],
            'hdmc': a['hdmc'],
            'hdms': a['hdms'],
            // 学校实测 bm 是 int/str 两态：mock 直接给 int 1/0，覆盖归一比较
            'bm': s.signedUpActivities.contains(id) ? 1 : 0,
          },
        });

      // 活动报名（学工工作流 hdsq）：先取动态表单定义（预填值全部由学校生成），
      // 再 urlencoded 平铺提交，成功返回工作流实例 ID——与真实系统同款协议。
      case '/zftal-xgxt-web/dynamic/form/find/hdsq/default.zf':
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        final dataId = req.uri.queryParameters['dataId'] ?? '';
        final aid = dataId.split('|').last;
        if (!_activityItems.containsKey(aid)) {
          return _json(res, {'code': 1, 'msg': '活动不存在'});
        }
        return _json(res, {
          'code': 0,
          'data': {
            'saveUrl': '/hdgl/flow/apply/hdsq.zf',
            'fields': [
              {'fieldCode': 'hdid', 'defaultValue': aid},
              {'fieldCode': 'xh', 'defaultValue': studentId},
              {'fieldCode': 'xm', 'defaultValue': realName},
              {'fieldCode': 'xb', 'defaultValue': '男'},
              {'fieldCode': 'csrq', 'defaultValue': '2006-01-01'},
              {'fieldCode': 'zzmm', 'defaultValue': '共青团员'},
              {'fieldCode': 'mz', 'defaultValue': '汉族'},
              {'fieldCode': 'sjh', 'defaultValue': '13800000000'},
              {'fieldCode': 'zjhm', 'defaultValue': '310101200601010011'},
              {'fieldCode': 'bmmc', 'defaultValue': '计算机学院'},
              {'fieldCode': 'zymc', 'defaultValue': '计算机科学与技术'},
              {'fieldCode': 'bjmc', 'defaultValue': '计科2501'},
              {'fieldCode': 'nj', 'defaultValue': '2025'},
              {'fieldCode': 'xnxq', 'defaultValue': '2025-2026-1'},
              {'fieldCode': 'hdkssj|hdjssj', 'defaultValue': '2026-10-10 14:00:00,2026-10-10 16:00:00'},
              {'fieldCode': 'dqxf', 'defaultValue': '5.5'},
              {'fieldCode': 'ljxf', 'defaultValue': '5.5'},
              {'fieldCode': 'bmfj', 'defaultValue': null}, // 附件字段：客户端应跳过
              {'fieldCode': 'grjs', 'defaultValue': ''},
              {'fieldCode': 'grgzjl', 'defaultValue': ''},
              {'fieldCode': 'hjry', 'defaultValue': ''},
              {'fieldCode': 'bmyy', 'defaultValue': ''},
              {'fieldCode': 'zyjn', 'defaultValue': ''},
            ],
          },
        });

      case '/zftal-xgxt-web/hdgl/flow/apply/hdsq.zf':
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        debugLastSignupForm = form;
        final aid = form['hdid'] ?? '';
        if (aid.isEmpty || form['xh'] != studentId || (form['hdkssj'] ?? '').isEmpty) {
          return _json(res, {'code': 1, 'msg': '报名表单校验失败'});
        }
        if (s.signedUpActivities.contains(aid)) {
          return _json(res, {'code': 1, 'msg': '该活动已报名，请勿重复报名'});
        }
        s.signedUpActivities.add(aid);
        return _json(res, {
          'code': 0,
          'data': {'instanceId': 'inst-${DateTime.now().millisecondsSinceEpoch}'},
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
    _text(res, 404, 'mock: 未实现的校园卡路径 $path', 'text/plain; charset=utf-8');
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

  /// 学业情况首页：复刻 SIT 这版真实页面的关键结构——
  /// 学号等隐藏域（明细 POST 要回传）、`div#alertBox` 整体统计、以及**写在 JS 模板
  /// 字符串里**的节点树：`<p class='title1' id='p<id>' yxxf='已获学分'
  /// yqzdxf='要求学分' sftg='0|1'>" + "类别名&nbsp;" + $.i18n.get('yqxf')/* 要求学分 */
  /// + ":33.0&nbsp;" ...`，父子关系在模板里的 `fxfyqjd_id='父id'`，
  /// 明细接口选择靠 `jdkcsx`（'1' = 教学计划；其它 = 非课程信息）。
  ///
  /// 这棵树刻意做到 5 层（主修 → 公共基础课 → 数理课程 → 高等数学 → 工科），
  /// 用来回归「深层嵌套把课程卡片挤扁」的布局问题；通识课下的叶子走非课程信息接口。
  static const String _academicIndexPage = '''
<html><body>
<h5>学生学业情况查询</h5>
<input type="hidden" name="xh_id" value="25110001" id="xh_id"/>
<input type="hidden" name="cjlrxn" value="2026" id="cjlrxn"/>
<input type="hidden" name="cjlrxq" value="3" id="cjlrxq"/>
<input type="hidden" name="bkcjlrxn" value="2026" id="bkcjlrxn"/>
<input type="hidden" name="bkcjlrxq" value="3" id="bkcjlrxq"/>
<input type="hidden" name="xscjcxkz" value="0" id="xscjcxkz"/>
<input type="hidden" name="cjcxkzzt" value="1" id="cjcxkzzt"/>
<input type="hidden" name="cjztkz" value="0" id="cjztkz"/>
<input type="hidden" name="cjzt" value="" id="cjzt"/>
<div id="alertBox">
  平均学分绩点：<font size="2px">3.52</font>&nbsp;
  计划总课程 60 门 通过 52 门 未通过 3 门 未修 4 门 在读 1 门，
  计划外 通过 3 门 未通过 1 门
</div>
<script>
\$("<ul id='ul1000'><li id='li1000' class='' fxfyqjd_id='' >" +
  "<div class='title' xfyqjd_id='1000' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1000' yxxf='52.5' yqzdxf='170' sftg='0'>" +
  "主修&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":170.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":52.5&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":117.5&nbsp;" +
  "<span id='showKc1000'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1100'><li id='li1100' class='' fxfyqjd_id='1000' >" +
  "<div class='title' xfyqjd_id='1100' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1100' yxxf='4.0' yqzdxf='8' sftg='0'>" +
  "通识课&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":8.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":4.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":4.0&nbsp;" +
  "<span id='showKc1100'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1110'><li id='li1110' class='' fxfyqjd_id='1100' >" +
  "<div class='title' xfyqjd_id='1110' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1110' yxxf='0.0' yqzdxf='0' sftg='1'>" +
  "人文精神与明德修养&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":0.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":0.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":0.0&nbsp;" +
  "<span id='showKc1110'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1111'><li id='li1111' class='' fxfyqjd_id='1100' >" +
  "<div class='title' xfyqjd_id='1111' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1111' yxxf='0.0' yqzdxf='2' sftg='0'>" +
  "科学精神与技术创新&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":2.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":0.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":2.0&nbsp;" +
  "<span id='showKc1111'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1112'><li id='li1112' class='' fxfyqjd_id='1100' >" +
  "<div class='title' xfyqjd_id='1112' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1112' yxxf='2.0' yqzdxf='2' sftg='1'>" +
  "企业文化与职业素养&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":2.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":2.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":0.0&nbsp;" +
  "<span id='showKc1112'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1113'><li id='li1113' class='' fxfyqjd_id='1100' >" +
  "<div class='title' xfyqjd_id='1113' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1113' yxxf='2.0' yqzdxf='2' sftg='1'>" +
  "公共艺术类课程&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":2.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":2.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":0.0&nbsp;" +
  "<span id='showKc1113'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1200'><li id='li1200' class='' fxfyqjd_id='1000' >" +
  "<div class='title' xfyqjd_id='1200' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1200' yxxf='33.5' yqzdxf='54' sftg='0'>" +
  "公共基础课&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":54.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":33.5&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":20.5&nbsp;" +
  "<span id='showKc1200'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1210'><li id='li1210' class='' fxfyqjd_id='1200' >" +
  "<div class='title' xfyqjd_id='1210' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1210' yxxf='13.5' yqzdxf='17.5' sftg='0'>" +
  "数理课程&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":17.5&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":13.5&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":4.0&nbsp;" +
  "<span id='showKc1210'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1211'><li id='li1211' class='' fxfyqjd_id='1210' >" +
  "<div class='title' xfyqjd_id='1211' jdkcsx='4' leaf='' sfmjd='1' ><p class='title1' id='p1211' yxxf='10.0' yqzdxf='10' sftg='1'>" +
  "高等数学&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":10.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":10.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":0.0&nbsp;" +
  "<span id='showKc1211'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1212'><li id='li1212' class='' fxfyqjd_id='1211' >" +
  "<div class='title' xfyqjd_id='1212' jdkcsx='1' leaf='' sfmjd='1' ><p class='title1' id='p1212' yxxf='10.0' yqzdxf='10' sftg='1'>" +
  "工科&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":10.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":10.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":0.0&nbsp;" +
  "<span id='showKc1212'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul1220'><li id='li1220' class='' fxfyqjd_id='1200' >" +
  "<div class='title' xfyqjd_id='1220' jdkcsx='1' leaf='' sfmjd='1' ><p class='title1' id='p1220' yxxf='11.0' yqzdxf='18' sftg='0'>" +
  "思政课程&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":18.0&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":11.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":7.0&nbsp;" +
  "<span id='showKc1220'></span></p></div></li></ul>").appendTo("body");
\$("<ul id='ul2000'><li id='li2000' class='' fxfyqjd_id='' >" +
  "<div class='title' xfyqjd_id='2000' jdkcsx='1' leaf='' sfmjd='1' ><p class='title1' id='p2000' yxxf='2.0' yqzdxf='' sftg='1'>" +
  "其他课程&nbsp;" + \$.i18n.get('yqxf')/* 要求学分 */ + ":&nbsp;" + \$.i18n.get('hdxf')/* 获得学分 */ + ":2.0&nbsp;&nbsp;" + \$.i18n.get('whdxf')/* 未获得学分 */ + ":&nbsp;" +
  "<span id='showKc2000'></span></p></div></li></ul>").appendTo("body");
</script>
</body></html>
''';

  /// 老版/静态方言的页面（节点直接渲染成 HTML，没有 JS 模板）：
  /// 用于回归「其它学校/旧版正方」的解析回退。
  static const String debugAcademicStaticPage = '''
<html><body>
<h5>学生学业情况查询</h5>
<form id="form"><input type="hidden" id="xh_id" value="25110001"/></form>
<div id="alertBox">
  平均学分绩点：<font size="2px">3.52</font>&nbsp;
  计划总课程 60 门 通过 52 门 未通过 3 门 未修 4 门 在读 1 门，
  计划外 通过 3 门 未通过 1 门
</div>
<div class="panel"><div class="panel-heading">
  <a data-toggle="collapse">专业核心课</a>
  <span>要求学分：33.0&nbsp;获得学分：28.0&nbsp;未获得学分：5.0</span>
  <span id='showKc9002'></span>
</div></div>
</body></html>
''';

  /// 学业情况节点课程明细（真实接口是大写字段，按 xfyqjd_id 分组）。
  /// 只放「教学计划课程」节点（jdkcsx='1'）；非课程节点见 [_academicNonCourses]。
  static const Map<String, List<Map<String, Object?>>> _academicCourses = {
    // 深层叶子：主修 → 公共基础课 → 数理课程 → 高等数学 → 工科（5 层）
    '1212': [
      {'KCH': 'MA1201', 'KCMC': '高等数学（工）2', 'XF': '4.0', 'KCXZMC': '必修',
        'KCLBMC': '数理课程', 'XDZT': '4', 'MAXCJ': '92', 'JD': '4.2',
        'JYXDXNM': '2026', 'JYXDXQMC': '第一学期'},
      {'KCH': 'MA1305', 'KCMC': '线性代数', 'XF': '2.0', 'KCXZMC': '必修',
        'KCLBMC': '数理课程', 'XDZT': '4', 'MAXCJ': '85', 'JD': '3.5',
        'JYXDXNM': '2026', 'JYXDXQMC': '第一学期'},
      // 在修（XDZT=1）：用于回归「在修」黄色标签
      {'KCH': 'MA1306', 'KCMC': '概率论与数理统计', 'XF': '3.0', 'KCXZMC': '必修',
        'KCLBMC': '数理课程', 'XDZT': '1', 'MAXCJ': '', 'JD': '',
        'JYXDXNM': '2026', 'JYXDXQMC': '第二学期'},
    ],
    '1220': [
      {'KCH': 'B1280001', 'KCMC': '形势与政策（1）', 'XF': '0.5', 'KCXZMC': '必修',
        'KCLBMC': '公共基础课', 'XDZT': '4', 'MAXCJ': '97', 'JD': '4.7',
        'JYXDXNM': '2025', 'JYXDXQMC': '第一学期'},
      {'KCH': 'B1280003', 'KCMC': '中国近现代史纲要', 'XF': '3.0', 'KCXZMC': '必修',
        'KCLBMC': '公共基础课', 'XDZT': '4', 'MAXCJ': '89', 'JD': '3.9',
        'JYXDXNM': '2025', 'JYXDXQMC': '第一学期'},
      // 未修（XDZT=3）：用于回归「未修」红色标签
      {'KCH': 'B1280005', 'KCMC': '思想道德与法治', 'XF': '3.0', 'KCXZMC': '必修',
        'KCLBMC': '公共基础课', 'XDZT': '3', 'MAXCJ': '', 'JD': '',
        'JYXDXNM': '2026', 'JYXDXQMC': '第二学期'},
    ],
    // 根节点直接挂课程（其他课程）
    '2000': [
      {'KCH': 'AI2201', 'KCMC': '人工智能导论', 'XF': '2.0', 'KCXZMC': '选修',
        'KCLBMC': '其他课程', 'XDZT': '4', 'MAXCJ': '88', 'JD': '3.3',
        'JYXDXNM': '2026', 'JYXDXQMC': '第二学期'},
      {'KCH': 'CS2301', 'KCMC': 'Python 编程实训', 'XF': '1.0', 'KCXZMC': '实践',
        'KCLBMC': '其他课程', 'XDZT': '4', 'MAXCJ': '95', 'JD': '4.5',
        'JYXDXNM': '2026', 'JYXDXQMC': '第二学期'},
    ],
    // 老版静态页面回归用例用（debugAcademicStaticPage 里的 showKc9002）
    '9002': [
      {'KCH': 'MA1102', 'KCMC': '高等数学(下)', 'XF': '4.0', 'KCXZMC': '必修',
        'KCLBMC': '专业核心课', 'XDZT': '1', 'MAXCJ': '92', 'JD': '4.2',
        'JYXDXNM': '2026', 'JYXDXQMC': '第一学期'},
      {'KCH': 'CS2101', 'KCMC': '数据结构', 'XF': '3.5', 'KCXZMC': '必修',
        'KCLBMC': '专业核心课', 'XDZT': '1', 'MAXCJ': '88', 'JD': '3.3',
        'JYXDXNM': '2026', 'JYXDXQMC': '第一学期'},
    ],
  };

  /// 「非课程信息」节点明细（jdkcsx != '1'）：通识课下的叶子节点走这个接口，
  /// 这正是「通识课有学分但 App 显示 0 门」的那个缺口。
  static const Map<String, List<Map<String, Object?>>> _academicNonCourses = {
    '1112': [
      {'KCH': 'GE1101', 'KCMC': '企业文化与职业素养（慕课）', 'XF': '2.0',
        'KCXZMC': '选修', 'KCLBMC': '通识课', 'XDZT': '4', 'MAXCJ': '85',
        'JD': '3.5', 'JYXDXNM': '2025', 'JYXDXQMC': '第一学期'},
    ],
    '1113': [
      {'KCH': 'GE1102', 'KCMC': '艺术鉴赏', 'XF': '2.0', 'KCXZMC': '选修',
        'KCLBMC': '通识课', 'XDZT': '4', 'MAXCJ': '90', 'JD': '4.0',
        'JYXDXNM': '2025', 'JYXDXQMC': '第一学期'},
    ],
    '1110': [],
    '1111': [],
  };

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
    'xh': studentId, 'xm': realName, 'nj': grade,
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
  final Set<String> signedUpActivities = {}; // 已报名活动（重复提交据此拒绝）
}
