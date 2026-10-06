import 'dart:typed_data';

import '../api_error.dart';
import 'activities_util.dart';
import 'crypto.dart';
import 'http_session.dart';

/// 学工（zftal-xgxt）客户端：统一身份认证 CAS 登录（AES 加密密码 + 图形验证码）、
/// 第二课堂分数、活动列表 / 详情。移植自 index 后端 campus/dekt.py；仅能在校园网 / 校内 VPN 下访问。
class XgClient {
  XgClient({required String authBase, required String xgBase})
      : authBase = authBase.replaceAll(RegExp(r'/+$'), ''),
        xgBase = xgBase.replaceAll(RegExp(r'/+$'), '') {
    _http = HttpSession(
      trustHosts: [Uri.parse(this.authBase).host, Uri.parse(this.xgBase).host],
      persistKey: 'direct_cookies_xg',
    );
  }

  final String authBase; // 统一身份认证（含 /authserver）
  final String xgBase; // 学工

  late final HttpSession _http;
  bool loggedIn = false;

  String? _studentId;
  String _password = '';
  String? _loginUrl;
  Map<String, String>? _fields;
  String? _salt;
  final Map<String, String> _hdmsCache = {};

  static int _ms() => DateTime.now().millisecondsSinceEpoch;
  String get _api => '$xgBase/zftal-xgxt-web';

  void dispose() => _http.dispose();

  /// 丢弃会话：登录态与 Cookie（含持久化的）一起清，下次调用重新走 CAS 登录。
  void clearSession() {
    loggedIn = false;
    _http.clearCookies();
  }

  Never _sessionLost() {
    loggedIn = false;
    _http.clearCookies();
    throw ApiError('学工登录已失效，请重新查询');
  }

  /// 可达性探测（连接设置页「测试连接」）。
  Future<String?> probe() async {
    final r = await _http.get('$_api/teacher/xtgl/index/check.zf', redirect: false);
    if (r.status >= 500) throw ApiError('学工系统返回 HTTP ${r.status}');
    return '可达（HTTP ${r.status}）';
  }

  dynamic _parse(HttpResult r) {
    final j = r.json;
    if (j is Map && j['isEncrypt'] == true) {
      final key = (j['key'] ?? 'data').toString();
      if (j[key] is String) j[key] = dektDecryptValue(j[key] as String, '');
    }
    return j;
  }

  static String? _hiddenField(String html, String name) =>
      RegExp('name="$name"[^>]*value="([^"]*)"').firstMatch(html)?.group(1);

  /// 加密盐：`<input ... id="pwdDefaultEncryptSalt" value="...">` 或 JS 变量。
  /// 不假设 id / value 的先后顺序（页面改版时 element 属性顺序并不稳定），引号单双都认。
  static String _findSalt(String html) {
    final tag = RegExp(r'<input[^>]*pwdDefaultEncryptSalt[^>]*>', caseSensitive: false)
        .firstMatch(html)
        ?.group(0);
    if (tag != null) {
      final v = RegExp('''value\\s*=\\s*["']([^"']+)["']''').firstMatch(tag)?.group(1);
      if (v != null && v.isNotEmpty) return v;
    }
    return RegExp('''pwdDefaultEncryptSalt\\s*[:=]\\s*["']([^"']+)["']''').firstMatch(html)?.group(1) ??
        '';
  }

  /// 取不到加密盐时的诊断：把「请求到了哪个页面、页面里有哪些要素」一并给出，
  /// 一眼能分清是登录页改版，还是压根没到统一认证（把这段截图给开发者即可）。
  static String _saltError(HttpResult page, String html, String loginUrl) {
    const marks = {
      'pwdDefaultEncryptSalt': '盐字段名',
      'auth_login_btn': '登录按钮',
      'captchaImg': '验证码图',
      'execution': 'CAS 令牌',
      'username': '用户名框',
      'publicKey': '公钥',
    };
    final found = [for (final e in marks.entries) if (html.contains(e.key)) e.value];
    final at = html.toLowerCase().indexOf('salt');
    final snippet = at < 0
        ? '（整页没有 salt 字样）'
        : '…${html.substring((at - 80).clamp(0, html.length), (at + 80).clamp(0, html.length)).replaceAll(RegExp(r'\s+'), ' ')}…';
    return '统一认证登录页异常（请求 $loginUrl → HTTP ${page.status} · ${page.url} · ${html.length} 字）：'
        '${found.isEmpty ? '页面上没有登录表单要素' : '命中 ${found.join('/')}'}，'
        '但取不到加密盐 pwdDefaultEncryptSalt。$snippet';
  }

  /// 学工会话是否已建立（统一认证 SSO 完成后的确认）。
  Future<bool> _currentUserOk() async {
    final cu = await _http.get('$_api/teacher/xtgl/login/getCurrentUser.zf');
    return cu.text.contains('"code":0');
  }

  static String _loginError(String html, String fallback) {
    // 金智 authserver 的错误提示元素各校不一：SIT 实测用 .auth_error / #usernameError /
    // #passwordError / #cpatchaError（页面里就这么拼的）/ #loginError，另有学校用 <span id="msg">。
    // 解析不出就只能给笼统文案，分辨不出「验证码错」还是「密码错」，所以逐个试。
    final rules = <RegExp>[
      RegExp(r'id="msg"[^>]*>(.*?)</(?:span|div)>', dotAll: true),
      RegExp(r'id="(?:username|password|cpatcha|captcha|login)Error"[^>]*>(.*?)</(?:span|div)>',
          dotAll: true),
      RegExp(r'class="[^"]*auth_error[^"]*"[^>]*>(.*?)</(?:span|div)>', dotAll: true),
    ];
    for (final re in rules) {
      final m = re.firstMatch(html);
      final msg = m == null ? '' : m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (msg.isNotEmpty) return msg;
    }
    return fallback;
  }

  String _absolute(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '${Uri.parse(_api).origin}$url';
    return '$_api/$url';
  }

  /// 开始 CAS 登录：返回验证码图片（已登录返回 null）。
  Future<Uint8List?> prepareLogin(String studentId, String password) async {
    _studentId = studentId;
    _password = password;
    String loginUrl;
    HttpResult page;
    final check = await _http.get('$_api/teacher/xtgl/index/check.zf', redirect: false);
    if (check.status >= 300 && check.status < 400 && check.location.isNotEmpty) {
      loginUrl = _absolute(check.location);
      page = await _http.get(loginUrl);
    } else {
      final cu = await _http.get('$_api/teacher/xtgl/login/getCurrentUser.zf');
      if (cu.text.contains('"code":0')) {
        loggedIn = true;
        return null;
      }
      loginUrl =
          '$authBase/login?service=${Uri.encodeComponent('$_api/teacher/xtgl/index/check.zf')}';
      page = await _http.get(loginUrl);
    }
    final html = page.text;
    final fields = <String, String>{};
    for (final name in ['execution', '_eventId', 'lt', 'rmShown', 'dllt', 'geolocation']) {
      final v = _hiddenField(html, name);
      if (v != null) fields[name] = v;
    }
    fields.putIfAbsent('dllt', () => 'userNamePasswordLogin');
    fields.putIfAbsent('_eventId', () => 'submit');
    _loginUrl = loginUrl;
    _fields = fields;
    _salt = _findSalt(html);
    if (_salt!.isEmpty) {
      // 统一认证会话（CASTGC）还有效时 authserver 不给登录页，而是直接 302 回业务系统——
      // 跟过去拿到的就是业务页，自然没有加密盐。这种「其实已经登录成功」的情形要认出来，
      // 否则用户会卡在一个根本不是登录页的页面上反复重试。
      if (await _currentUserOk()) {
        loggedIn = true;
        return null;
      }
      throw ApiError(_saltError(page, html, loginUrl));
    }
    final cap = await _http.get('$authBase/captcha.html?ts=${_ms()}');
    return cap.body;
  }

  /// 用验证码完成 CAS 登录。
  Future<void> completeLogin(String captcha) async {
    final fields = _fields;
    final loginUrl = _loginUrl;
    if (fields == null || loginUrl == null) throw ApiError('登录会话已过期，请重新登录');
    final pwd = wiseduEncryptPassword(_password, _salt ?? '');
    final resp = await _http.postForm(
      loginUrl.split('?').first,
      {
        ...fields,
        'username': _studentId ?? '',
        'password': pwd,
        'captchaResponse': captcha,
      },
      headers: {'Referer': loginUrl},
    );
    _fields = null;
    _loginUrl = null;
    final cu = await _http.get('$_api/teacher/xtgl/login/getCurrentUser.zf');
    if (!cu.text.contains('"code":0')) {
      throw ApiError(_loginError(resp.text, '统一认证登录失败（验证码错误或账号密码错误）'));
    }
    loggedIn = true;
  }

  // ==================== 第二课堂分 ====================

  /// 查询第二课堂得分（德智体美劳细分）。
  Future<Map<String, dynamic>> score(String studentId) async {
    if (!loggedIn) throw ApiError('未登录学工系统');
    final resp = await _http.postForm(
      '$_api/xsrdtjcx/getAllXslbTjcx.zf',
      {'currentPage': '1', 'pageSize': '15', 'showCount': '10', 'xh': studentId},
      headers: {'Referer': '$xgBase/dektxf/xfqktj'},
      redirect: false,
    );
    if (resp.status >= 300 && resp.status < 400) _sessionLost();
    final j = _parse(resp);
    if (j is! Map) _sessionLost();
    if (j['code'] != 0) throw ApiError((j['msg'] ?? '查询失败').toString());
    return _buildScoreView(j);
  }

  static Map<String, dynamic> _buildScoreView(Map j) {
    final queryModel = (j['queryModel'] as Map?) ?? const {};
    final items = (queryModel['items'] as List?) ?? const [];
    final header = (j['tableHeader'] as List?) ?? const [];
    if (items.isEmpty) {
      return {'student': {}, 'total': null, 'credit': null, 'groups': []};
    }
    final it = (items.first as Map?) ?? const {};
    final groups = <String, Map<String, dynamic>>{};
    for (final raw in header) {
      final h = raw is Map ? raw : const {};
      final fc = (h['fieldCode'] ?? '').toString();
      final name = (h['fieldName'] ?? fc).toString();
      final grp = (h['fieldTh'] ?? '其他').toString();
      if (['xh', 'xm', 'nj', 'bmmc', 'zymc', 'bjmc', 'zxs', 'sjxf', 'sjxs'].contains(fc)) {
        continue;
      }
      final g = groups.putIfAbsent(grp, () => {'subtotal': null, 'rows': []});
      if (fc.startsWith('dlxs')) {
        g['subtotal'] = it[fc];
      } else if (fc.startsWith('rdxs')) {
        (g['rows'] as List).add({'name': name, 'value': it[fc]});
      }
    }
    return {
      'student': {
        'xh': it['xh'],
        'xm': it['xm'],
        'nj': it['nj'],
        'bmmc': it['bmmc'],
        'zymc': it['zymc'],
        'bjmc': it['bjmc'],
      },
      'total': it['zxs'],
      'credit': it['sjxf'],
      'groups': [
        for (final e in groups.entries)
          {'name': e.key, 'subtotal': e.value['subtotal'], 'rows': e.value['rows']},
      ],
    };
  }

  // ==================== 第二课堂活动 ====================

  Map<String, String> get _xgHeaders => {
        'Origin': xgBase,
        'Referer': '$xgBase/hdgl/hdydlist',
        'Accept': 'application/json, text/plain, */*',
        'X-Requested-With': 'XMLHttpRequest',
      };

  /// 活动引导页全部活动，按 大类/类别 展开为扁平列表（补充 _dlmc/_lbmc）。
  Future<List<Map<String, dynamic>>> fetchActivities() async {
    if (!loggedIn) throw ApiError('未登录学工系统');
    final resp = await _http.postJson('$_api/hdgl/getHdgcHdList.zf', {}, headers: _xgHeaders);
    final j = _parse(resp);
    if (j is! Map || j['code'] != 0) _sessionLost();
    final out = <Map<String, dynamic>>[];
    for (final gRaw in ((j['data'] as Map?)?['resultList'] as List?) ?? const []) {
      final g = gRaw is Map ? gRaw : const {};
      for (final lbRaw in (g['lblist'] as List?) ?? const []) {
        final lb = lbRaw is Map ? lbRaw : const {};
        for (final hdRaw in (lb['hdlist'] as List?) ?? const []) {
          final hd = Map<String, dynamic>.from(hdRaw is Map ? hdRaw : const {});
          hd['_dlmc'] = g['dlmc'];
          hd['_lbmc'] = lb['lbmc'];
          final cached = _hdmsCache[hd['id']];
          if (cached != null && (hd['hdms'] ?? '').toString().isEmpty) hd['hdms'] = cached;
          out.add(hd);
        }
      }
    }
    return out;
  }

  /// 单个活动详情（hdms 活动说明全文），说明写入缓存供列表复用。
  Future<Map<String, dynamic>> fetchActivityDetail(Object id) async {
    if (!loggedIn) throw ApiError('未登录学工系统');
    final resp = await _http
        .get('$_api/hdgl/details.zf?id=${Uri.encodeComponent('$id')}', headers: _xgHeaders);
    final j = _parse(resp);
    if (j is! Map || j['code'] != 0) _sessionLost();
    final data = Map<String, dynamic>.from((j['data'] as Map?) ?? const {});
    final hdms = (data['hdms'] ?? '').toString();
    if (hdms.isNotEmpty) _hdmsCache['$id'] = hdms;
    return data;
  }

  /// 活动看板载荷（列表 + 学号），与开放接口 /activities 的 data 同形。
  Future<Map<String, dynamic>> activitiesPayload() async {
    final acts = (await fetchActivities()).map(activitySnapshot).toList();
    return {'activities': acts, 'student_id': _studentId};
  }
}
