import 'dart:typed_data';

import '../api_error.dart';
import 'crypto.dart';
import 'http_session.dart';

/// 32 位十六进制 GUID：部分课程的 kcb_id 是内部 ID（如毛概），不能当课程代码展示。
final RegExp _guidRe = RegExp(r'^[0-9A-Fa-f]{32}$');

/// 考试时间 kssj，如 2026-06-23(10:15-11:45)。
final RegExp _kssjRe = RegExp(r'^(\d{4}-\d{2}-\d{2})\((\d{1,2}:\d{2})-(\d{1,2}:\d{2})\)');

String readableCourseCode(List<Object?> candidates) {
  for (final c in candidates) {
    final v = (c ?? '').toString().trim();
    if (v.isNotEmpty && !_guidRe.hasMatch(v)) return v;
  }
  return '';
}

/// 正方教务客户端：登录（RSA 加密密码 + 图形验证码）、成绩、周课表、考试安排。
/// 移植自 index 后端 campus/dekt.py 的教务部分；仅能在校园网 / 校内 VPN 下访问。
class JwxtClient {
  JwxtClient(String base, {this.aesKey = ''}) : base = base.replaceAll(RegExp(r'/+$'), '') {
    _http = HttpSession(
      trustHosts: [Uri.parse(this.base).host],
      persistKey: 'direct_cookies_jwxt',
    );
  }

  final String base;
  final String aesKey; // isEncrypt 响应解密密钥，留空表示不加密

  late final HttpSession _http;
  bool loggedIn = false;

  String? _studentId;
  String? _csrftoken;
  String? _encPassword;

  static int _ms() => DateTime.now().millisecondsSinceEpoch;
  String get _jwglxt => '$base/jwglxt';

  void dispose() => _http.dispose();

  /// 丢弃会话：登录态与 Cookie（含持久化的）一起清，下次调用重新走登录流程。
  void clearSession() {
    loggedIn = false;
    _http.clearCookies();
  }

  /// 探测持久化 Cookie 是否仍有效，避免每次启动都要输验证码。
  Future<bool> checkSession() async {    try {
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
    throw ApiError('教务登录已失效，请重新导入/查询');
  }

  /// 会话是否已失效：正方对过期会话的接口请求不一定回 302，也可能回 200 + 登录页 HTML
  /// （有些版本），甚至回一段不含预期字段的 JSON。
  /// 这些都必须按「会话失效」处理：否则 loggedIn 一直是 true，之后每次查询都会同样失败，
  /// 课表还会被误报成「该周没有课表数据」而静默不显示——只能靠手动清会话才恢复。
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

  /// 学校原文里的错误文案（如「验证码错误」「用户名或密码错误」）。
  /// 正方各版本把提示塞在不同元素里，SIT 新版登录页的文案还可能是 JS 写进去的、服务端返回的
  /// HTML 里根本没有，所以先按元素找，再退一步找「像一句话」的文本节点。
  /// 文本节点必须同时含提示对象（验证码/密码/账号/用户名）与错误词，否则会抓到页面里的
  /// `<label>验证码</label>` 这类静态文案，把「页面改版」误判成「验证码错误」。
  static String _schoolTip(String html) {
    for (final re in <RegExp>[
      RegExp(r'id="(?:tips|msg|tipsMsg|errorMsg|loginError)"[^>]*>(.*?)</(?:div|span|p|em|strong)>',
          dotAll: true),
      RegExp(r'class="[^"]*(?:tips|error|msg)[^"]*"[^>]*>(.*?)</(?:div|span|p|em|strong)>',
          dotAll: true),
    ]) {
      final m = re.firstMatch(html);
      final t = m == null ? '' : m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (t.isNotEmpty) return t;
    }
    for (final m in RegExp(r'>([^<>]{1,60})<').allMatches(html)) {
      final t = m.group(1)!.trim();
      if (t.isEmpty) continue;
      if (!RegExp(r'验证码|密码|账号|用户名').hasMatch(t)) continue;
      if (!RegExp(r'错误|不正确|失效|过期|为空|不存在|无效|请输入').hasMatch(t)) continue;
      return t;
    }
    return '';
  }

  /// 登录失败的提示：学校给了文案就用原文（含「验证码」→ 上层换张验证码重输，否则直接失败）。
  /// 取不到就如实说「学校页面没有错误文案」，并把页面片段一并带上——不要退化成全页搜「验证码」
  /// 二字：那样会抓到 HTML 注释里的 `验证码-->` 之类碎片，既说不清失败原因，又因为含「验证码」
  /// 被当成验证码错误，白白重试三次。
  static String _loginError(HttpResult r) {
    final tip = _schoolTip(r.text);
    if (tip.isNotEmpty) return tip;
    return '教务登录未通过（HTTP ${r.status}，学校登录页没有错误文案，可能是登录页改版）：'
        '${_pageSnippet(r.text)}';
  }

  /// 页面片段（压掉空白、限长）：给开发者定位用，别再猜。先去掉 HTML 注释——
  /// 注释里常留着 `<!--验证码-->` 这种模板垃圾，留着只会继续误导。
  static String _pageSnippet(String html) {
    final text = html
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return '（学校返回了空页面）';
    final at = text.indexOf('验证码');
    final start = (at < 0 ? 0 : at - 60).clamp(0, text.length);
    final end = (start + 160).clamp(0, text.length);
    return '${start > 0 ? '…' : ''}${text.substring(start, end).trim()}'
        '${end < text.length ? '…' : ''}';
  }

  /// 准备登录：抓 csrftoken + 公钥加密密码 + 验证码图片；返回验证码图片字节。
  Future<Uint8List> prepareLogin(String studentId, String password) async {
    _studentId = studentId;
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
    if (resp.status != 302) throw ApiError(_loginError(resp));
    loggedIn = true;
  }

  Map<String, String> get _jwxtHeaders => {
        'Referer':
            '$base/jwglxt/kbcx/xskbcxMobile_cxXsKb.html?gnmkdm=N2154&layout=default',
        'X-Requested-With': 'XMLHttpRequest',
        'Origin': base,
      };

  // ==================== 成绩 ====================

  Map<String, String> _gradesBody(String xnm, String xqm) => {
        'xnm': xnm,
        'xqm': xqm,
        'sfzgcj': '',
        'kcbj': '',
        'pkey': '',
        '_search': 'false',
        'nd': '${_ms()}',
        'queryModel.showCount': '15',
        'queryModel.currentPage': '1',
        'queryModel.sortName': ' ',
        'queryModel.sortOrder': 'asc',
        'time': '0',
      };

  /// 成绩单 + 绩点；xnm/xqm 都为空时查全部学期并返回 terms。
  Future<Map<String, dynamic>> grades(String studentId,
      {String xnm = '', String xqm = ''}) async {
    if (!loggedIn) throw ApiError('未登录教务系统');
    final resp = await _http.postForm(
      '$_jwglxt/cjcx/cjcx_cxXsgrcj.html?doType=query&gnmkdm=N305005',
      _gradesBody(xnm, xqm),
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
    final grades = <Map<String, dynamic>>[];
    for (final raw in items) {
      final it = raw is Map ? raw : const {};
      grades.add({
        'kcmc': it['kcmc'],
        'cj': it['cj'],
        'xf': it['xf'],
        'jd': it['jd'],
        'xfjd': it['xfjd'],
        'kclbmc': it['kclbmc'],
        'kcxzmc': it['kcxzmc'],
        'khfsmc': it['khfsmc'],
        'xqmmc': it['xqmmc'],
        'xnmmc': it['xnmmc'],
        'sfxwkc': it['sfxwkc'],
      });
    }
    final result = _calcGpa(grades);
    if (xnm.isEmpty && xqm.isEmpty) {
      final terms = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final raw in items) {
        final it = raw is Map ? raw : const {};
        final k1 = it['xnm'], k2 = it['xqm'];
        if (k1 == null || k2 == null) continue;
        final key = '$k1|$k2';
        if (seen.add(key)) {
          terms.add({
            'xnm': k1,
            'xqm': k2,
            'xnmmc': (it['xnmmc'] ?? '').toString(),
            'xqmmc': (it['xqmmc'] ?? '').toString(),
          });
        }
      }
      terms.sort((a, b) {
        final c = (a['xnmmc'] as String).compareTo(b['xnmmc'] as String);
        return c != 0 ? c : (a['xqm'] as String).compareTo(b['xqm'] as String);
      });
      result['terms'] = terms;
    }
    return result;
  }

  /// 绩点 = 成绩/10 - 5（满绩点 5.0）；总绩点 = Σ(绩点×学分)/Σ学分。
  static Map<String, dynamic> _calcGpa(List<Map<String, dynamic>> grades) {
    var totalXfjd = 0.0;
    var totalXf = 0.0;
    for (final g in grades) {
      double jd;
      final cj = g['cj'];
      final cjF = cj == null ? null : double.tryParse(cj.toString());
      if (cjF == null) {
        jd = double.tryParse((g['jd'] ?? '0').toString()) ?? 0;
      } else {
        jd = double.parse((cjF / 10.0 - 5.0).toStringAsFixed(4));
      }
      final xfF = double.tryParse((g['xf'] ?? '').toString()) ?? 0.0;
      final xfjd = double.parse((jd * xfF).toStringAsFixed(4));
      g['jd'] = jd;
      g['xfjd'] = xfjd;
      totalXfjd += xfjd;
      totalXf += xfF;
    }
    return {
      'grades': grades,
      'gpa': totalXf == 0 ? 0 : double.parse((totalXfjd / totalXf).toStringAsFixed(4)),
      'count': grades.length,
    };
  }

  // ==================== 课表（移动端按周查询） ====================

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
    final courses = <Map<String, dynamic>>[];
    for (final raw in (j is Map ? (j['kbList'] as List?) ?? const [] : const [])) {
      final it = raw is Map ? raw : const {};
      int slotStart, slotEnd, day;
      try {
        final jcs = (it['jcs'] ?? '').toString();
        if (jcs.contains('-')) {
          final parts = jcs.split('-');
          slotStart = int.parse(parts[0]) - 1;
          slotEnd = int.parse(parts[1]) - 1;
        } else {
          slotStart = slotEnd = int.parse(jcs) - 1;
        }
        day = (int.parse((it['xqj'] ?? '1').toString()) - 1).clamp(0, 6);
      } catch (_) {
        continue;
      }
      if (slotStart < 0 || slotEnd < slotStart || slotEnd >= 11) continue;
      courses.add({
        'name': (it['kcmc'] ?? '').toString().trim(),
        'place': (it['cdmc'] ?? '').toString().trim(),
        'teachers': (it['xm'] ?? '').toString().trim(),
        'code': readableCourseCode([it['kcb_id'], it['kch_id'], it['kch']]),
        'clazz': (it['jxbmc'] ?? it['jxb_id'] ?? '').toString().trim(),
        'day': day,
        'slotStart': slotStart,
        'slotEnd': slotEnd,
      });
    }
    final xsxx = (j is Map ? (j['xsxx'] as Map?) : null) ?? const {};
    return {
      'courses': courses,
      'dates': [
        for (final raw in rqazc)
          if (raw is Map) {'xqj': raw['xqj'], 'rq': raw['rq']},
      ],
      'xnmc': (xsxx['XNMC'] ?? '').toString(),
      'nj': (xsxx['NJDM_ID'] ?? '').toString(),
    };
  }

  // ==================== 考试安排 ====================

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
    final exams = <Map<String, dynamic>>[];
    for (final raw in items) {
      final it = raw is Map ? raw : const {};
      final m = _kssjRe.firstMatch((it['kssj'] ?? '').toString().trim());
      if (m == null) continue; // 解析不了的格式跳过
      String hm(String s) => '${s.split(':')[0].padLeft(2, '0')}:${s.split(':')[1]}';
      exams.add({
        'name': (it['kcmc'] ?? '').toString().trim(),
        'ksmc': (it['ksmc'] ?? '').toString().trim(),
        'date': m.group(1),
        'start': hm(m.group(2)!),
        'end': hm(m.group(3)!),
        'place': (it['cdmc'] ?? '').toString().trim(),
        'seat': (it['zwh'] ?? '').toString().trim(),
        'ksfs': (it['ksfs'] ?? '').toString().trim(),
      });
    }
    return exams;
  }
}
