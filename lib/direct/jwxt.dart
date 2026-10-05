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

  static String _loginError(String html) {
    final m = RegExp(r'id="tips"[^>]*>(.*?)</', dotAll: true).firstMatch(html);
    final tips = m == null ? '' : m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    if (tips.isNotEmpty) return tips;
    final m2 = RegExp('验证码[^<]{0,20}').firstMatch(html);
    return (m2 != null && m2.group(0)!.trim().isNotEmpty)
        ? m2.group(0)!.trim()
        : '教务登录失败（验证码错误或账号密码错误）';
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
    if (resp.status != 302) throw ApiError(_loginError(resp.text));
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
    if (resp.status == 302) _sessionLost();
    final j = _parse(resp);
    final items = j is Map ? j['items'] : null;
    if (items is! List) {
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
    if (resp.status == 302 || resp.status == 901) _sessionLost();
    final j = _parse(resp);
    final rqazc = j is Map ? j['rqazcList'] : null;
    if (rqazc is! List || rqazc.isEmpty) {
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
    if (resp.status == 302 || resp.status == 901) _sessionLost();
    final j = _parse(resp);
    final items = j is Map ? j['items'] : null;
    if (items is! List) {
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
