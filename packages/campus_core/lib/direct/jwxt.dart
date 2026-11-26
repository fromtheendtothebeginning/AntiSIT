import 'package:flutter/foundation.dart';

import '../api_error.dart';
import 'academic.dart';
import 'cas.dart';
import 'course_select.dart';
import 'crypto.dart';
import 'http_session.dart';
import 'jwxt_login_html.dart';
import 'jwxt_parser.dart';

export 'jwxt_parser.dart';

part 'jwxt_courses.dart';

/// 正方教务客户端：登录（RSA 加密密码 + 图形验证码）、成绩、周课表、考试安排。
///
/// 账号密码被拒时由 [enableCasLogin] 切到统一身份认证（CAS），密码仍是同一个。
class JwxtClient {
  JwxtClient(String base,
      {this.aesKey = '', String authBase = '', bool allowSelfSigned = false})
      : base = base.replaceAll(RegExp(r'/+$'), ''),
        authBase = authBase.replaceAll(RegExp(r'/+$'), '') {
    _http = HttpSession(
      trustHosts: [
        Uri.parse(this.base).host,
        if (this.authBase.isNotEmpty) Uri.parse(this.authBase).host,
      ],
      persistKey: 'direct_cookies_jwxt',
      allowSelfSigned: allowSelfSigned,
    );
  }

  final String base;
  final String aesKey; // isEncrypt 响应解密密钥，留空表示不加密
  final String authBase; // 统一身份认证（含 /authserver），用于 CAS 登录

  late final HttpSession _http;
  bool loggedIn = false;

  String? _studentId;
  String? _csrftoken;
  String? _encPassword;
  String? _plainPassword; // CAS 登录提交时用（正方登录用 _encPassword）
  CasLogin? _cas;
  String? _ssoEntry;

  /// 当前登录是否已切到统一身份认证（账号密码被拒之后）。
  bool get usingCasLogin => _cas != null;

  static int _ms() => DateTime.now().millisecondsSinceEpoch;
  String get _jwglxt => '$base/jwglxt';

  void dispose() => _http.dispose();

  /// 当前教务会话的 Cookie（name → value），供评教助手把登录态带进 WebView。
  Future<Map<String, String>> cookies() => _http.cookiesFor(Uri.parse(base).host);

  /// 丢弃会话：登录态与 Cookie（含持久化的）一起清，下次调用重新走登录流程。
  void clearSession() {
    loggedIn = false;
    _http.clearCookies();
  }

  /// 探测持久化 Cookie 是否仍有效，避免每次启动都要输验证码。
  Future<bool> checkSession() async {
    try {
      final r = await _http.get('$_jwglxt/xtgl/index_initMenu.html', redirect: false);
      if (r.status >= 300) return false;
      final t = r.text;
      if (t.contains('login_slogin') || t.contains('login_getPublicKey')) return false;
      loggedIn = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 会话失效：清登录态，调用方提示重新查询。
  Never _sessionLost() {
    loggedIn = false;
    _http.clearCookies();
    throw ApiError('教务登录已失效，请重新导入/查询', null, null, true);
  }

  /// 会话是否已失效：过期会话可能回 302，也可能回 200 + 登录页 HTML 或不含预期字段的 JSON。
  bool _deadSession(HttpResult r) =>
      r.status == 302 ||
      r.status == 901 ||
      r.text.contains('login_slogin') ||
      r.text.contains('login_getPublicKey');

  /// 可达性探测（连接设置页「测试连接」）：能取到教务登录页即视为可达。
  Future<String?> probe() async {
    final html = (await _http.get('$_jwglxt/xtgl/login_slogin.html')).text;
    if (html.contains('login_slogin') || html.contains('csrftoken')) return '可达（教务登录页正常）';
    if (html.contains('jwglxt')) return '可达';
    throw ApiError('返回内容不是教务登录页，请核对该校教务域名');
  }

  dynamic _parse(HttpResult r) {
    final j = r.json;
    if (j is Map && j['isEncrypt'] == true) {
      final key = (j['key'] ?? 'data').toString();
      if (j[key] is String) j[key] = dektDecryptValue(j[key] as String, aesKey);
    }
    return j;
  }

  /// 账号密码登录被拒后改用登录页上的「统一身份认证」入口（CAS）；false = 没有可用入口。
  Future<bool> enableCasLogin() async {
    if (_cas != null) return true;
    // 失败的正方登录会话没有复用价值，留着可能把 CAS 回跳的 ticket 绑到旧会话上。
    _http.clearCookies();
    String html;
    try {
      html = (await _http.get('$_jwglxt/xtgl/login_slogin.html')).text;
    } catch (_) {
      return false;
    }
    final pageUrl = '$_jwglxt/xtgl/login_slogin.html';
    final candidates = <String>[
      // 学校官方的门户→教务单点入口：带统一认证会话访问，有 CASTGC 时直接放行建会话。
      '$base/sso/jziotlogin',
      for (final u in ssoEntries(html)) Uri.parse(pageUrl).resolve(u).toString(),
      // 正方新版的统一认证入口路径：登录页按钮是 JS 跳转、解析不到时兜底。
      '$_jwglxt/xtgl/login_ssologin.html',
      '$_jwglxt/xtgl/login_sloginCAS.html',
    ];
    final seen = <String>{};
    for (final url in candidates) {
      if (!seen.add(url)) continue;
      final cas = CasLogin(http: _http, authBase: authBase);
      try {
        if (await cas.open(url)) {
          _cas = cas;
          _ssoEntry = url;
          _encPassword = null;
          return true;
        }
        // 入口直接放行（持久化的统一认证会话还在）：会话已建好，不需要 CAS 表单。
        if (await checkSession()) {
          loggedIn = true;
          return true;
        }
      } catch (_) {
        // 这个入口不通，试下一个
      }
    }
    return false;
  }

  /// 登录页里的统一认证入口（原始 href/action，可能相对路径）；抽成静态方法便于单测。
  @visibleForTesting
  static List<String> ssoEntries(String html) {
    final out = <String>[];
    void add(String raw) {
      final v = raw.trim();
      if (v.isEmpty || v.startsWith('#') || v.startsWith('javascript:')) return;
      if (v.contains('login_getPublicKey') || v.contains('/kaptcha')) return;
      final casLike = RegExp(
              r'(login_ssologin|login_sloginCAS|casLogin|ssoLogin|authserver|/cas/|authType=cas|loginType=cas)',
              caseSensitive: false)
          .hasMatch(v);
      if (casLike) out.add(v);
    }

    for (final m in RegExp(r'''(?:href|action|src|url)\s*[=:]\s*["']([^"']+)["']''',
            caseSensitive: false)
        .allMatches(html)) {
      add(m.group(1)!);
    }
    // 入口写在脚本里（location.href = '...' / window.open(...)）时没有 href 属性
    for (final m in RegExp(r'''["']((?:https?:)?//[^"']+|/[^"']+)["']''').allMatches(html)) {
      add(m.group(1)!);
    }
    // 按钮文字是「统一身份认证」但 href 本身不含关键词的情况
    for (final m in RegExp(
            r'''<a\b[^>]*href=["']([^"']+)["'][^>]*>[^<]*(?:统一身份认证|统一认证|CAS|SSO)[^<]*</a>''',
            caseSensitive: false,
            dotAll: true)
        .allMatches(html)) {
      add(m.group(1)!);
    }
    return out;
  }

  /// 准备登录：抓 csrftoken + 公钥加密密码 + 验证码图片；返回验证码图片字节。
  Future<Uint8List> prepareLogin(String studentId, String password) async {
    _studentId = studentId;
    final cas = _cas;
    if (cas != null) {
      _plainPassword = password;
      // 每次尝试都重新打开入口：失败一次后 execution 令牌已作废，复用会一直报验证码错。
      if (!await cas.open(_ssoEntry!)) {
        if (await checkSession()) {
          loggedIn = true;
          return Uint8List(0);
        }
        throw ApiError('统一身份认证入口已失效，请稍后重试');
      }
      return cas.captcha();
    }
    final html = (await _http.get('$_jwglxt/xtgl/login_slogin.html')).text;
    _csrftoken = RegExp(r'name="csrftoken"[^>]*value="([^"]*)"').firstMatch(html)?.group(1) ?? '';
    final kd = (await _http.get('$_jwglxt/xtgl/login_getPublicKey.html?time=${_ms()}')).json;
    if (kd is! Map || kd['modulus'] == null || kd['exponent'] == null) {
      throw ApiError('教务系统公钥获取失败：请确认已连接校园网/校内 VPN 后重试');
    }
    _encPassword = rsaEncryptPkcs1(password, kd['modulus'].toString(), kd['exponent'].toString());
    final cap = await _http.get('$_jwglxt/kaptcha?time=${_ms()}');
    return cap.body;
  }

  /// 用验证码完成登录；验证码或账号密码错误抛 ApiError。
  Future<void> completeLogin(String captcha) async {
    final cas = _cas;
    if (cas != null) {
      final pwd = _plainPassword;
      if (pwd == null) throw ApiError('教务登录会话已过期，请重新登录');
      final resp = await cas.submit(_studentId ?? '', pwd, captcha);
      _plainPassword = null;
      if (await checkSession()) {
        loggedIn = true;
        return;
      }
      final tip = CasLogin.errorTip(resp.text);
      throw ApiError(tip.isNotEmpty
          ? tip
          : '统一身份认证登录未通过（HTTP ${resp.status}），请稍后重试');
    }
    final enc = _encPassword;
    if (enc == null) throw ApiError('教务登录会话已过期，请重新登录');
    final resp = await _http.postForm(
      '$_jwglxt/xtgl/login_slogin.html?time=${_ms()}',
      {
        'yhm': _studentId ?? '',
        'mm': enc,
        'yzm': captcha,
        'csrftoken': _csrftoken ?? '',
        'language': 'zh_CN',
      },
      redirect: false,
    );
    _encPassword = null;
    if (resp.status != 302) {
      // 少数版本登录成功也不回 302（直接 200 渲染首页 / 返回跳转脚本），拿会话探活兜一次。
      if (await checkSession()) return;
      throw ApiError(loginErrorMessage(resp));
    }
    loggedIn = true;
  }

  Map<String, String> get _jwxtHeaders => {
        'Referer':
            '$base/jwglxt/kbcx/xskbcxMobile_cxXsKb.html?gnmkdm=N2154&layout=default',
        'X-Requested-With': 'XMLHttpRequest',
        'Origin': base,
      };

  Map<String, String> _gradesBody(String xnm, String xqm, {int page = 1}) => {
        'xnm': xnm,
        'xqm': xqm,
        'sfzgcj': '',
        'kcbj': '',
        'pkey': '',
        '_search': 'false',
        'nd': '${_ms()}',
        'queryModel.showCount': '$_gradesPageSize',
        'queryModel.currentPage': '$page',
        'queryModel.sortName': ' ',
        'queryModel.sortOrder': 'asc',
        'time': '0',
      };

  /// 正方分页每页条数；按页取全，避免只拿第 1 页漏掉后面的学期。
  static const int _gradesPageSize = 100;

  /// 成绩单 + 绩点；xnm/xqm 都为空时查全部学期并返回 terms。
  Future<Map<String, dynamic>> grades(String studentId,
      {String xnm = '', String xqm = ''}) async {
    if (!loggedIn) throw ApiError('未登录教务系统');
    final raw = <Object?>[]; // 保留原始 item：学期列表也要从全量里取
    for (var page = 1; page <= _gradesMaxPages; page++) {
      final resp = await _http.postForm(
        '$_jwglxt/cjcx/cjcx_cxXsgrcj.html?doType=query&gnmkdm=N305005',
        _gradesBody(xnm, xqm, page: page),
        headers: {
          'Referer':
              '$base/jwglxt/cjcx/cjcx_cxDgXscj.html?gnmkdm=N305005&layout=default',
          'X-Requested-With': 'XMLHttpRequest',
          'Origin': base,
        },
        redirect: false,
      );
      if (_deadSession(resp)) _sessionLost();
      final j = _parse(resp);
      final items = j is Map ? j['items'] : null;
      if (items is! List) {
        if (j == null) _sessionLost(); // 不是 JSON：被学校打回登录页/门户页了
        final t = resp.text;
        throw ApiError('教务系统查询失败（${resp.status}）：${t.length > 200 ? t.substring(0, 200) : t}');
      }
      raw.addAll(items);
      final total = j is Map
          ? (int.tryParse('${j['totalResult'] ?? j['totalCount'] ?? ''}') ?? 0)
          : 0;
      if (total > 0) {
        if (raw.length >= total) break; // 拿齐了
      } else if (items.isEmpty || items.length < _gradesPageSize) {
        // 学校不回总数时按「短页」判结束（空页也结束）
        break;
      }
    }
    final grades = parseJwxtGradeRows(raw);
    final result = computeJwxtGpa(grades);
    if (xnm.isEmpty && xqm.isEmpty) {
      result['terms'] = parseJwxtTerms(raw);
    }
    return result;
  }

  /// 分页兜底上限：学校不返回 totalResult 时靠「短页」结束，这里防止异常时无限拉取。
  static const int _gradesMaxPages = 30;

  /// 查询某周课表：courses + 该周日期安排 + 学期名/年级（nj 用于「大一上~大四下」锚定）。
  Future<Map<String, dynamic>> kbcx(String studentId, String xnm, String xqm, int zs) async {
    if (!loggedIn) throw ApiError('未登录教务系统');
    final resp = await _http.postForm(
      '$base/jwglxt/kbcx/xskbcxMobile_cxXsKb.html?gnmkdm=N2154',
      {
        'gnmkdm': 'N2154',
        'xnm': xnm,
        'xqm': xqm,
        'zs': '$zs',
        'doType': 'app',
        'kblx': '1',
        'xh': studentId,
      },
      headers: _jwxtHeaders,
      redirect: false,
    );
    if (_deadSession(resp)) _sessionLost();
    final j = _parse(resp);
    final rqazc = j is Map ? j['rqazcList'] : null;
    if (rqazc is! List || rqazc.isEmpty) {
      if (j == null) _sessionLost(); // 不是 JSON：多半是登录页，别误报成「这周没课」
      throw ApiError('该周没有课表数据（可能已超出学期范围）');
    }
    final courses = parseJwxtWeekCourses(
        j is Map ? (j['kbList'] as List?) ?? const [] : const []);
    final xsxx = (j is Map ? (j['xsxx'] as Map?) : null) ?? const {};
    return {
      'courses': courses,
      'dates': parseJwxtWeekDates(rqazc),
      'xnmc': (xsxx['XNMC'] ?? '').toString(),
      'nj': (xsxx['NJDM_ID'] ?? '').toString(),
    };
  }

  /// 考试查询（正方桌面接口）：xnm=学年（如 2025），xqm=学期码（第一学期 3 / 第二学期 12）。
  Future<List<Map<String, dynamic>>> exams(String xnm, String xqm) async {
    if (!loggedIn) throw ApiError('未登录教务系统');
    final resp = await _http.postForm(
      '$base/jwglxt/kwgl/kscx_cxXsksxxIndex.html?doType=query&gnmkdm=N358105',
      {
        'xnm': xnm,
        'xqm': xqm,
        'ksmcdmb_id': '',
        'kch': '',
        'kc': '',
        'ksrq': '',
        'kkbm_id': '',
        '_search': 'false',
        'nd': '${_ms()}',
        'queryModel.showCount': '100',
        'queryModel.currentPage': '1',
        'queryModel.sortName': ' ',
        'queryModel.sortOrder': 'asc',
        'time': '1',
      },
      headers: {
        'Referer':
            '$base/jwglxt/kwgl/kscx_cxXsksxxIndex.html?gnmkdm=N358105&layout=default',
        'X-Requested-With': 'XMLHttpRequest',
        'Origin': base,
      },
      redirect: false,
    );
    if (_deadSession(resp)) _sessionLost();
    final j = _parse(resp);
    final items = j is Map ? j['items'] : null;
    if (items is! List) {
      if (j == null) _sessionLost(); // 不是 JSON：被学校打回登录页/门户页了
      final t = resp.text;
      throw ApiError('教务系统查询失败（${resp.status}）：${t.length > 200 ? t.substring(0, 200) : t}');
    }
    return parseJwxtExams(items);
  }

  /// 学业情况：整体统计（GPA / 计划内外课程通过数）+ 各课程类别学分要求 + 类别课程明细。
  Future<Map<String, dynamic>> academicStatus() async {
    if (!loggedIn) throw ApiError('未登录教务系统');
    final page = await _http.get(
      '$_jwglxt$academicIndexPath',
      headers: {'Referer': '$base/jwglxt/xtgl/index_initMenu.html'},
      redirect: false,
    );
    if (_deadSession(page)) _sessionLost();
    final parsed = parseAcademicIndex(page.text);
    if (parsed['login'] == true) _sessionLost(); // 200 + 登录页 HTML
    final err = '${parsed['error'] ?? ''}'.trim();
    if (err.isNotEmpty) throw ApiError('学业情况查询失败：$err');

    // 页面结构完全对不上（既没学号/统计，也没有任何类别）时不要返回空数据：
    // 用户会以为「真的没有学业数据」，而实际是教务改版或回了别的页面。
    final stats = (parsed['statistics'] as Map?) ?? const {};
    final hasAny = '${parsed['sid'] ?? ''}'.trim().isNotEmpty ||
        stats['gpa'] != null ||
        stats['planed'] != null ||
        stats['unplaned'] != null ||
        ((parsed['categories'] as List?) ?? const []).isNotEmpty;
    if (!hasAny) {
      throw ApiError('学业情况页面解析失败（页面结构可能已改版）：${loginPageSnippet(page.text)}');
    }

    final sid = '${parsed['sid'] ?? ''}';
    final cats = ((parsed['categories'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    // 只有叶子节点能取到课程明细：父节点的明细接口回空数组，父节点集合由各节点的
    // parent 字段反推，避免白打一轮请求。
    final parentIds = <String>{
      for (final c in cats)
        if ('${c['parent'] ?? ''}'.trim().isNotEmpty) '${c['parent']}'.trim(),
    };
    final params = ((parsed['params'] as Map?) ?? const {}).cast<String, String>();
    final leaves = cats.where((c) {
      final id = '${c['id'] ?? ''}'.trim();
      return id.isNotEmpty && !parentIds.contains(id);
    }).toList();

    // 并行拉（都是只读请求，会话共享没问题）：单个节点失败不拖垮整页，标 coursesError 交给 UI。
    await Future.wait(leaves.map((cat) async {
      final id = '${cat['id']}'.trim();
      try {
        // 真实页面按节点属性 jdkcsx 选接口：'1' 走教学计划课程，其它走「非课程信息」；
        // 属性缺失时先走教学计划接口，空了再兜底一次。
        final isPlanCourse = '${cat['jdkcsx'] ?? ''}'.trim() == '1';
        final firstPath = isPlanCourse ? academicCoursesPath : academicNonCoursePath;
        final ok = await _fetchCourses(cat, {
          ...params,
          'fromXh_id': '',
          'xfyqjd_id': id,
        }, sid: sid, path: firstPath);
        final empty = ((cat['courses'] as List?) ?? const []).isEmpty;
        if (ok && empty) {
          await _fetchCourses(cat, {
            ...params,
            'fromXh_id': '',
            'xfyqjd_id': id,
          },
              sid: sid,
              path: isPlanCourse ? academicNonCoursePath : academicCoursesPath);
        }
      } on ApiError catch (e) {
        if (e.sessionLost) rethrow; // 会话失效要走自动重登
        cat['courses'] = const [];
        cat['coursesError'] = e.message;
      }
    }));
    for (final c in cats) {
      c.putIfAbsent('courses', () => const []);
    }
    return parsed;
  }

  /// 拉一个节点的课程明细；返回 false 表示响应不是 JSON（接口改版），原因写进 `coursesError`。
  Future<bool> _fetchCourses(
    Map<String, dynamic> cat,
    Map<String, String> body, {
    required String sid,
    String path = academicCoursesPath,
  }) async {
    final resp = await _http.postForm(
      '$_jwglxt$path',
      body,
      headers: _jwxtHeaders,
      redirect: false,
    );
    if (_deadSession(resp)) _sessionLost();
    final j = _parse(resp);
    if (j == null) {
      cat['courses'] = const [];
      cat['coursesError'] = 'HTTP ${resp.status}';
      return false;
    }
    final courses = parseAcademicCourses(j, sid: sid);
    cat['courses'] = courses;
    if (courses.isNotEmpty) cat.remove('coursesError');
    return true;
  }
}
