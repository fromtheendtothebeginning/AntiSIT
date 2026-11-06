import 'package:flutter/foundation.dart';

import '../api_error.dart';
import 'academic.dart';
import 'cas.dart';
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
///
/// 登录有两条路：正方自己的账号密码表单；以及登录页上的「统一身份认证」入口（CAS）。
/// 新生等账号可能在正方侧没有可用密码（浏览器里也只能点统一认证登入），
/// 账号密码被拒时由 [enableCasLogin] 切到 SSO，密码仍是同一个统一身份认证密码。
class JwxtClient {
  JwxtClient(String base, {this.aesKey = '', String authBase = ''})
      : base = base.replaceAll(RegExp(r'/+$'), ''),
        authBase = authBase.replaceAll(RegExp(r'/+$'), '') {
    _http = HttpSession(
      trustHosts: [
        Uri.parse(this.base).host,
        if (this.authBase.isNotEmpty) Uri.parse(this.authBase).host,
      ],
      persistKey: 'direct_cookies_jwxt',
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
  /// 元素规则与文本节点一样要过语义门槛（提示对象 + 错误词缺一不可）：新版登录页有
  /// `class="tipsqrcode"` 的微信扫码区块（命中 tips）和 `<!-- 0-弹出验证码-->` 这类模板
  /// 注释（尾巴 `验证码-->`），不过门槛就会被当成错误文案——前者被直接抛给用户，
  /// 后者因含「验证码」被误当成验证码错误白白重试三次。
  /// 另外登录页普遍带 `style="display:none"` 的**静态**错误骨架（「请输入用户名 / 请输入密码 /
  /// 请输入验证码」），它们是给 JS 改文案用的、永远不出现在屏幕上；服务端的判定结果一律渲染在
  /// 可见元素里（如 `#tips`）。抓隐藏元素同样会误报（把「请输入密码」当成账号密码错误抛给用户），
  /// 所以隐藏元素一律跳过——按元素抓和按文本节点抓都要跳，否则兜底那条把骨架又捞回来了。
  static String _schoolTip(String html) {
    // 注释与脚本先剥掉：注释里常留 `<!-- 0-弹出验证码-->` 这类模板尾巴；
    // <script> 里则是登录页的静态提示文案（如「用户名或密码错误」的 JS 分支），
    // 它们都不是服务端对本次登录的判定结果，抓走就会把失败原因张冠李戴。
    final clean = _stripNoise(html);
    final obj = RegExp(r'验证码|密码|账号|用户名');
    final err = RegExp(r'错误|不正确|失效|过期|为空|不存在|无效|请输入');
    final hidden = RegExp(r'display\s*:\s*none|visibility\s*:\s*hidden', caseSensitive: false);
    // 闭合标签按同名标签配对：正方 `#tips` 里先有一个空 `<span class="glyphicon"></span>` 再跟文案，
    // 若匹配到任意闭合标签就收尾（原来的 `</(?:div|span|p|...)>`），只会拿到那个空 span；
    // 文案虽还能被下面的文本节点兜底捞到，但超过 60 字就会被截断/漏掉。
    for (final re in <RegExp>[
      RegExp(r'<([a-zA-Z][\w]*)\b[^>]*id="(?:tips|msg|tipsMsg|errorMsg|loginError)"[^>]*>(.*?)</\1>',
          dotAll: true),
      RegExp(r'<([a-zA-Z][\w]*)\b[^>]*class="[^"]*(?:tips|error|msg)[^"]*"[^>]*>(.*?)</\1>',
          dotAll: true),
    ]) {
      for (final m in re.allMatches(clean)) {
        if (hidden.hasMatch(m.group(0)!)) continue;
        final t = m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        if (t.isEmpty) continue;
        if (!obj.hasMatch(t) || !err.hasMatch(t)) continue;
        return t;
      }
    }
    for (final m in RegExp(r'>([^<>]{1,60})<').allMatches(clean)) {
      final t = m.group(1)!.trim();
      if (t.isEmpty) continue;
      if (!obj.hasMatch(t)) continue;
      if (!err.hasMatch(t)) continue;
      // 这段文本所在的开始标签若带 display:none / visibility:hidden，它同样是隐藏骨架
      // （骨架元素之外包了别的标签时，上面按时元素抓的那轮会漏掉，这里必须自己判一次）
      if (_enclosingTagHidden(clean, m.start, hidden)) continue;
      return t;
    }
    return '';
  }

  /// [textStart] 处文本的直接外层开始标签里是否带隐藏样式。
  static bool _enclosingTagHidden(String html, int textStart, RegExp hidden) {
    final open = html.lastIndexOf('<', textStart);
    if (open < 0) return false;
    final close = html.indexOf('>', open);
    if (close < 0 || close > textStart) return false;
    return hidden.hasMatch(html.substring(open, close + 1));
  }

  /// 登录失败的提示：学校给了文案就用原文（含「验证码」→ 上层换张验证码重输，否则直接失败）。
  /// 取不到就如实说「学校页面没有错误文案」，并把页面片段一并带上——不要退化成全页搜「验证码」
  /// 二字：那样会抓到 HTML 注释里的 `验证码-->` 之类碎片，既说不清失败原因，又因为含「验证码」
  /// 被当成验证码错误，白白重试三次。
  static String _loginError(HttpResult r) {
    final tip = _schoolTip(r.text);
    debugPrint('[教务登录] HTTP ${r.status} tip=[$tip] ${_pageSnippet(r.text)}');
    if (tip.isNotEmpty) return tip;
    return '教务登录未通过（HTTP ${r.status}，学校登录页没有错误文案，可能是登录页改版）：'
        '${_pageSnippet(r.text)}';
  }

  /// 给登录页 HTML 去噪：注释、<script>、<style>、以及带 display:none / visibility:hidden 的
  /// 元素整块删掉。它们要么是模板垃圾、要么是给 JS 改写用的静态骨架，都不是服务端对本次登录的
  /// 判定结果——留着只会被当成错误原因（「请输入密码」）抛给账号密码正确的用户。
  /// 但 html / body 例外：正方新版登录页用 `<body style="...display:none">` 防闪屏，由 JS 显示；
  /// 整块删会把正文（含服务端渲染好的可见 #tips）全删掉，登录失败就永远只剩「没有错误文案」。
  static String _stripNoise(String html) => html
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ')
      .replaceAll(RegExp(r'<script\b.*?</script>', dotAll: true, caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<style\b.*?</style>', dotAll: true, caseSensitive: false), ' ')
      .replaceAll(
          RegExp(
              r'<(?!html\b|body\b)(\w+)\b[^>]*(?:display\s*:\s*none|visibility\s*:\s*hidden)[^>]*>[\s\S]*?</\1>',
              dotAll: true,
              caseSensitive: false),
          ' ');

  /// 页面片段（压掉空白、限长）：给开发者定位用，别再猜。
  /// 先 [_stripNoise] 洗一遍（注释 / 脚本 / 隐藏骨架），窗口对准「错误 / 密码 / 验证码」
  /// 这类关键词——留在页面上的可见文案才是能被用户看到的失败原因。
  static String _pageSnippet(String html) {
    final text = _stripNoise(html).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return '（学校返回了空页面）';
    var at = -1;
    for (final kw in ['错误', '不正确', '无效', '验证码', '失败']) {
      at = text.indexOf(kw);
      if (at >= 0) break;
    }
    final start = (at < 0 ? 0 : at - 60).clamp(0, text.length);
    final end = (start + 160).clamp(0, text.length);
    return '${start > 0 ? '…' : ''}${text.substring(start, end).trim()}'
        '${end < text.length ? '…' : ''}';
  }

  /// 账号密码登录被学校拒绝后，改用登录页上的「统一身份认证」入口（CAS）。
  /// 新生账号常见：正方侧没有可用密码，浏览器里也是点统一认证按钮登入。
  /// 返回 false 表示登录页没有可用入口（学校未开 SSO / 登录页改版 / 不可达）。
  Future<bool> enableCasLogin() async {
    if (_cas != null) return true;
    // 失败的正方登录会话没有复用价值，留着反而可能把 CAS 回跳的 ticket 绑到旧会话上。
    _http.clearCookies();
    String html;
    try {
      html = (await _http.get('$_jwglxt/xtgl/login_slogin.html')).text;
    } catch (_) {
      return false;
    }
    final pageUrl = '$_jwglxt/xtgl/login_slogin.html';
    final candidates = <String>[
      for (final u in ssoEntries(html)) Uri.parse(pageUrl).resolve(u).toString(),
      // 正方新版的统一认证入口路径：登录页按钮是 JS 跳转、解析不到时兜底
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
      } catch (_) {
        // 这个入口不通，试下一个
      }
    }
    return false;
  }

  /// 登录页里的统一认证入口（原始 href/action，可能相对路径）。抽成静态方法便于单测。
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
      // 少数版本的教务登录成功也不回 302（直接 200 渲染首页 / 返回一段跳转脚本）。
      // 拿会话探活兜一次：能进 index_initMenu 就是登录成功，别把成功当失败报「账号密码错误」。
      if (await checkSession()) return;
      throw ApiError(_loginError(resp));
    }
    loggedIn = true;
  }

  Map<String, String> get _jwxtHeaders => {
        'Referer':
            '$base/jwglxt/kbcx/xskbcxMobile_cxXsKb.html?gnmkdm=N2154&layout=default',
        'X-Requested-With': 'XMLHttpRequest',
        'Origin': base,
      };

  // ==================== 成绩 ====================

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

  /// 正方分页每页条数。原来固定 showCount=15 且只取第 1 页，成绩按学年升序返回，
  /// 于是「全部学期」永远只看到大一那十几门，大二以后全被截掉（学期筛选项也只有大一的）。
  static const int _gradesPageSize = 100;

  /// 成绩单 + 绩点；xnm/xqm 都为空时查全部学期并返回 terms。
  /// 逐页拉全（每页 [_gradesPageSize] 条），按 totalResult / 短页判结束。
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
    final grades = <Map<String, dynamic>>[];
    for (final it in raw.map((e) => e is Map ? e : const <String, dynamic>{})) {
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
      for (final it in raw.whereType<Map>()) {
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

  /// 分页兜底上限：学校不返回 totalResult 时靠「短页」结束，这里防止异常时无限拉取。
  static const int _gradesMaxPages = 30;

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

  // ==================== 学业情况（学生学业情况查询） ====================

  /// 学业情况：整体统计（GPA / 计划内外课程通过数）+ 各课程类别学分要求 + 类别课程明细。
  ///
  /// 首页 `xsxyqk_cxXsxyqkIndex.html` 是服务端渲染 HTML（学号、整体统计、类别节点与
  /// `showKc<id>` 占位都在里面）；每个类别的课程再 POST `xsxyqk_cxJxzxjhxfyqKcxx.html`
  /// （`xfyqjd_id=<id>`）取 JSON 数组。协议见 [academic.dart] 顶部注释。
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

    // 页面结构完全对不上（既没学号 / 统计，也没有任何类别）时不要返回空数据：
    // 用户会以为「真的没有学业数据」，而实际是教务改版或回了别的页面。
    final stats = (parsed['statistics'] as Map?) ?? const {};
    final hasAny = '${parsed['sid'] ?? ''}'.trim().isNotEmpty ||
        stats['gpa'] != null ||
        stats['planed'] != null ||
        stats['unplaned'] != null ||
        ((parsed['categories'] as List?) ?? const []).isNotEmpty;
    if (!hasAny) {
      throw ApiError('学业情况页面解析失败（页面结构可能已改版）：${_pageSnippet(page.text)}');
    }

    final sid = '${parsed['sid'] ?? ''}';
    final cats = ((parsed['categories'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    // 只有叶子节点能取到课程明细：父节点（主修 / 通识课 / 公共基础课…）的明细接口
    // 返回空数组，课程都在叶子节点下（真实页面也是点叶子才拉）。父节点集合从
    // 各节点的 parent 字段反推，避免白打一轮请求。
    final parentIds = <String>{
      for (final c in cats)
        if ('${c['parent'] ?? ''}'.trim().isNotEmpty) '${c['parent']}'.trim(),
    };
    final params = ((parsed['params'] as Map?) ?? const {}).cast<String, String>();
    final leaves = cats.where((c) {
      final id = '${c['id'] ?? ''}'.trim();
      return id.isNotEmpty && !parentIds.contains(id);
    }).toList();

    // 并行拉（都是只读 GET/POST，会话共享没问题）：27 个节点串行要好几秒，
    // 并行基本等于最慢那一次；单个节点失败不拖垮整页，标 coursesError 交给 UI。
    await Future.wait(leaves.map((cat) async {
      final id = '${cat['id']}'.trim();
      try {
        final resp = await _http.postForm(
          '$_jwglxt$academicCoursesPath',
          {...params, 'fromXh_id': '', 'xfyqjd_id': id},
          headers: _jwxtHeaders,
          redirect: false,
        );
        if (_deadSession(resp)) _sessionLost();
        final j = _parse(resp);
        if (j == null) {
          // 接口改版/被学校改回 HTML 时，别静默当成「该类没有课」：
          // 明确标记失败，UI 可以提示，也方便用户反馈截图。
          cat['courses'] = const [];
          cat['coursesError'] = 'HTTP ${resp.status}';
          return;
        }
        cat['courses'] = parseAcademicCourses(j, sid: sid);
      } on ApiError catch (e) {
        if (e.message.contains('失效')) rethrow; // 会话失效要走自动重登
        cat['courses'] = const [];
        cat['coursesError'] = e.message;
      }
    }));
    for (final c in cats) {
      c.putIfAbsent('courses', () => const []);
    }
    return parsed;
  }
}
