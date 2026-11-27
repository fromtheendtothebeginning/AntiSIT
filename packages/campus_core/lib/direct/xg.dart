import 'package:flutter/foundation.dart';

import '../api_error.dart';
import 'activities_util.dart';
import 'crypto.dart';
import 'xg_parser.dart';
import 'http_session.dart';

/// 学工（zftal-xgxt）客户端：统一身份认证 CAS 登录、第二课堂分数、活动列表 / 详情 / 报名。
class XgClient {
  XgClient({
    required String authBase,
    required String xgBase,
    bool allowSelfSigned = false,
  }) : authBase = authBase.replaceAll(RegExp(r'/+$'), ''),
       xgBase = xgBase.replaceAll(RegExp(r'/+$'), '') {
    _http = HttpSession(
      trustHosts: [Uri.parse(this.authBase).host, Uri.parse(this.xgBase).host],
      persistKey: 'direct_cookies_xg',
      allowSelfSigned: allowSelfSigned,
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
    throw ApiError('学工登录已失效，请重新查询', null, null, true);
  }

  /// 可达性探测（连接设置页「测试连接」）。
  Future<String?> probe() async {
    final r = await _http.get(
      '$_api/teacher/xtgl/index/check.zf',
      redirect: false,
    );
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

  /// 学工会话是否已建立（统一认证 SSO 完成后的确认）。
  Future<bool> _currentUserOk() async {
    final cu = await _http.get('$_api/teacher/xtgl/login/getCurrentUser.zf');
    return cu.text.contains('"code":0');
  }

  /// 相对路径补全为学工系统的绝对地址。
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
    final check = await _http.get(
      '$_api/teacher/xtgl/index/check.zf',
      redirect: false,
    );
    if (check.status >= 300 &&
        check.status < 400 &&
        check.location.isNotEmpty) {
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
    for (final name in [
      'execution',
      '_eventId',
      'lt',
      'rmShown',
      'dllt',
      'geolocation',
    ]) {
      final v = xgHiddenField(html, name);
      if (v != null) fields[name] = v;
    }
    fields.putIfAbsent('dllt', () => 'userNamePasswordLogin');
    fields.putIfAbsent('_eventId', () => 'submit');
    _loginUrl = loginUrl;
    _fields = fields;
    _salt = xgFindSalt(html);
    if (_salt!.isEmpty) {
      // 统一认证会话（CASTGC）还有效时 authserver 会 302 回业务页、拿不到加密盐；
      // 这种「其实已登录」的情形要认出来，否则用户会卡在业务页上反复重试。
      if (await _currentUserOk()) {
        loggedIn = true;
        return null;
      }
      throw ApiError(xgSaltError(page, html, loginUrl));
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
      // 可见错误文案才是学校对本次登录的判定；取不到时按 POST 是否被重定向区分票据回跳失败。
      final tip = xgLoginErrorTip(resp.text, '');
      if (tip.isNotEmpty) throw ApiError(tip);
      final accepted = resp.status >= 300 && resp.status < 400;
      throw ApiError(
        accepted
            ? '统一身份认证已通过，但学工系统会话没建起来（可能是系统繁忙或网络抖动），请稍后重试'
            : '统一认证登录未通过（HTTP ${resp.status}，学校页面没有错误文案），请稍后重试',
      );
    }
    loggedIn = true;
  }

  /// 查询第二课堂得分（德智体美劳细分）。
  Future<Map<String, dynamic>> score(String studentId) async {
    if (!loggedIn) throw ApiError('未登录学工系统');
    final resp = await _http.postForm(
      '$_api/xsrdtjcx/getAllXslbTjcx.zf',
      {
        'currentPage': '1',
        'pageSize': '15',
        'showCount': '10',
        'xh': studentId,
      },
      headers: {'Referer': '$xgBase/dektxf/xfqktj'},
      redirect: false,
    );
    if (resp.status >= 300 && resp.status < 400) _sessionLost();
    final j = _parse(resp);
    if (j is! Map) _sessionLost();
    if (j['code'] != 0) throw ApiError((j['msg'] ?? '查询失败').toString());
    return xgScoreView(j);
  }

  Map<String, String> get _xgHeaders => {
    'Origin': xgBase,
    'Referer': '$xgBase/hdgl/hdydlist',
    'Accept': 'application/json, text/plain, */*',
    'X-Requested-With': 'XMLHttpRequest',
  };

  /// 活动引导页全部活动，按 大类/类别 展开为扁平列表（补充 _dlmc/_lbmc）。
  Future<List<Map<String, dynamic>>> fetchActivities() async {
    if (!loggedIn) throw ApiError('未登录学工系统');
    final resp = await _http.postJson(
      '$_api/hdgl/getHdgcHdList.zf',
      {},
      headers: _xgHeaders,
    );
    final j = _parse(resp);
    // 只有「根本不是 JSON」（被打回登录页 / 门户页）才算会话失效；
    // code != 0 是学校的业务结果（系统繁忙、无权限…），按原文抛给用户。
    if (j is! Map) _sessionLost();
    if (j['code'] != 0) throw ApiError('${j['msg'] ?? '查询活动失败'}');
    final out = <Map<String, dynamic>>[];
    for (final gRaw
        in ((j['data'] as Map?)?['resultList'] as List?) ?? const []) {
      final g = gRaw is Map ? gRaw : const {};
      for (final lbRaw in (g['lblist'] as List?) ?? const []) {
        final lb = lbRaw is Map ? lbRaw : const {};
        for (final hdRaw in (lb['hdlist'] as List?) ?? const []) {
          final hd = Map<String, dynamic>.from(hdRaw is Map ? hdRaw : const {});
          hd['_dlmc'] = g['dlmc'];
          hd['_lbmc'] = lb['lbmc'];
          final cached = _hdmsCache[hd['id']];
          if (cached != null && (hd['hdms'] ?? '').toString().isEmpty) {
            hd['hdms'] = cached;
          }
          out.add(hd);
        }
      }
    }
    return out;
  }

  /// 单个活动详情（hdms 活动说明全文），说明写入缓存供列表复用。
  Future<Map<String, dynamic>> fetchActivityDetail(Object id) async {
    if (!loggedIn) throw ApiError('未登录学工系统');
    final resp = await _http.get(
      '$_api/hdgl/details.zf?id=${Uri.encodeComponent('$id')}',
      headers: _xgHeaders,
    );
    final j = _parse(resp);
    if (j is! Map) _sessionLost();
    if (j['code'] != 0) throw ApiError('${j['msg'] ?? '查询活动详情失败'}');
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

  /// 报名状态码（学校 `hdbmzt`）→ 中文；未知返回空串。
  static String hdStatusText(Object? code) => switch ('$code') {
    '1' => '流程设置中',
    '2' => '报名已截止',
    '3' => '报名未开始',
    '4' => '报名已满',
    '5' => '已报名',
    '6' => '无需报名',
    _ => '',
  };

  /// 已报名的第二课堂活动（本人报名记录）。
  ///
  /// ⚠️ 必须用 bizFlow `groupCode=xshd`：hdgl/list.zf 匿名可访问、返回的是公共活动池，不是本人报名。
  Future<List<Map<String, dynamic>>> signedActivities({
    int maxPages = 10,
  }) async {
    if (!loggedIn) throw ApiError('未登录学工系统');
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    var total = 0;
    for (var page = 1; page <= maxPages; page++) {
      final resp = await _http.postForm(
        '$_api/bizFlow/result/group/list.zf',
        {'groupCode': 'xshd', 'currentPage': '$page', 'showCount': '100'},
        headers: _xgHeaders,
        redirect: false,
      );
      if (resp.status >= 300 && resp.status < 400) _sessionLost();
      final j = _parse(resp);
      final data = j is Map ? j['data'] : null;
      final rows = data is Map ? data['rows'] as List? : null;
      if (rows == null) {
        if (j == null) _sessionLost();
        throw ApiError('我的报名查询失败（${resp.status}）');
      }
      final reportedTotal = int.tryParse(
        '${data is Map ? data['totalCount'] ?? '' : ''}',
      );
      if (reportedTotal != null && reportedTotal > 0) total = reportedTotal;
      for (final raw in rows) {
        final it = raw is Map ? raw : const {};
        final name = (it['hdmc'] ?? '').toString().trim();
        final activityId = '${it['hdid'] ?? ''}';
        if (name.isEmpty || activityId.isEmpty) continue;
        // 翻页期间同一报名实例可能跨页重复：按流程实例 ID 去重。
        final instanceId = '${it['INSTANCE_ID'] ?? it['ID'] ?? ''}'.trim();
        if (instanceId.isNotEmpty && !seen.add(instanceId)) continue;
        // 审批流状态 → 页面报名状态语义：通过 = 已报名（绿色胶囊），其余透传原文。
        final flow = (it['flowstatusmc'] ?? it['FLOWSTATUS'] ?? '')
            .toString()
            .trim();
        final statusText = flow == '通过' ? '已报名' : flow;
        out.add({
          'id': activityId,
          'name': name,
          'dlmc': (it['dldm'] ?? '').toString(),
          'lbmc': (it['lbmc'] ?? '').toString(),
          'start': it['hdkssj'],
          'end': it['hdjssj'],
          'place': (it['hddd'] ?? '').toString(),
          'status_text': statusText,
          'signed': true,
        });
      }
      // 学校若把 showCount 截到更小：有 totalCount 按总数续页，否则「不满一页即结束」。
      if (rows.isEmpty) break;
      if (total > 0) {
        if (out.length >= total) break;
      } else if (rows.length < 100) {
        break;
      }
    }
    return out;
  }

  /// 第二课堂加分明细（groupCode=xsrd 的学分认定结果，学分在 rdxs 字段）。
  Future<List<Map<String, dynamic>>> creditRecords({int maxPages = 10}) async {
    if (!loggedIn) throw ApiError('未登录学工系统');
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    var total = 0;
    for (var page = 1; page <= maxPages; page++) {
      final resp = await _http.postForm(
        '$_api/bizFlow/result/group/list.zf',
        {'groupCode': 'xsrd', 'currentPage': '$page', 'showCount': '100'},
        headers: _xgHeaders,
        redirect: false,
      );
      if (resp.status >= 300 && resp.status < 400) _sessionLost();
      final j = _parse(resp);
      final data = j is Map ? j['data'] : null;
      final rows = data is Map ? data['rows'] as List? : null;
      if (rows == null) {
        if (j == null) _sessionLost();
        throw ApiError('加分明细查询失败（${resp.status}）');
      }
      final reportedTotal = int.tryParse(
        '${data is Map ? data['totalCount'] ?? '' : ''}',
      );
      if (reportedTotal != null && reportedTotal > 0) total = reportedTotal;
      for (final raw in rows) {
        final it = raw is Map ? raw : const {};
        final name = (it['hdmc'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        // 翻页期间学校数据变动可能让同一工作流实例出现在两页里：按实例 ID 去重。
        final instanceId = '${it['INSTANCE_ID'] ?? it['ID'] ?? ''}'.trim();
        if (instanceId.isNotEmpty && !seen.add(instanceId)) continue;
        out.add({
          'id': '${it['INSTANCE_ID'] ?? it['ID'] ?? name}',
          'name': name,
          'dldm': (it['dldm'] ?? '').toString(),
          'lbdm': (it['lbdm'] ?? '').toString(),
          // 认定学分：xsrd 组在 rdxs（认定学分）/ xss；旧字段链兜底，取到为止。
          'credit':
              '${it['rdxs'] ?? it['xss'] ?? it['hdxf'] ?? it['jcxsxf'] ?? ''}',
          'status': (it['flowstatusmc'] ?? it['FLOWSTATUS'] ?? '').toString(),
          'start': it['hdkssj'],
          'end': it['hdjssj'],
          'date': it['CREATE_TIME'],
        });
      }
      // 学校若把 showCount 截到更小（比如一页 50），不能因为“本页不满 100”就收手：
      // 有 totalCount 时按总数续页，没有时才用旧的「不满一页即结束」规则。
      if (rows.isEmpty) break;
      if (total > 0) {
        if (out.length >= total) break;
      } else if (rows.length < 100) {
        break;
      }
    }
    return out;
  }

  /// 扫码签到 / 签退（hdId / hdActId 来自签到二维码路径段）。
  ///
  /// 写操作：只提交一次、绝不重试；会话失效时学校没见到提交，重登后重试一次是安全的。
  Future<Map<String, dynamic>> signInOrSignOut(
    Object hdId,
    Object hdActId,
  ) async {
    if (!loggedIn) throw ApiError('未登录学工系统');
    final resp = await _http.postForm(
      '$_api/hdgl/flow/signInOrSignOut.zf',
      {'hdId': '$hdId', 'hdActId': '$hdActId'},
      headers: _xgHeaders,
      redirect: false,
    );
    if (resp.status >= 300 && resp.status < 400) _sessionLost();
    final r = _parse(resp);
    if (r is! Map) _sessionLost();
    final msg = (r['msg'] ?? '').toString();
    if (r['code'] != 0) {
      throw ApiError(msg.isNotEmpty ? msg : '签到未成功（HTTP ${resp.status}）');
    }
    return {'msg': msg};
  }

  /// 报名（培训）二维码的扫码签到（hdgl/shsj/qd.zf，与签到 / 签退是不同接口）。
  ///
  /// 写操作：只提交一次、绝不重试；code != 0 抛 ApiError(学校原文)。
  Future<Map<String, dynamic>> trainingSignIn(Object hdId, Object pxId) async {
    if (!loggedIn) throw ApiError('未登录学工系统');
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final qdsj =
        '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    final resp = await _http.postForm(
      '$_api/hdgl/shsj/qd.zf',
      {'hdid': '$hdId', 'pxid': '$pxId', 'qdsj': qdsj},
      headers: _xgHeaders,
      redirect: false,
    );
    if (resp.status >= 300 && resp.status < 400) _sessionLost();
    final r = _parse(resp);
    if (r is! Map) _sessionLost();
    final msg = (r['msg'] ?? '').toString();
    if (r['code'] != 0) {
      throw ApiError(msg.isNotEmpty ? msg : '签到未成功（HTTP ${resp.status}）');
    }
    return {'msg': msg};
  }

  static const String _signupUrlPath = '/hdgl/flow/apply/hdsq.zf';
  static const String _signupFormUrlPath = '/dynamic/form/find/hdsq/default.zf';

  /// 取报名动态表单定义。GET 是幂等读，可以安全重试：学校前置 WAF 偶发
  /// `Connection closed while receiving data`（issue #17 截图里的那条），一次失败不代表报名不了。
  Future<HttpResult> _signupFormWithRetry(Object id) async {
    var lastError = '';
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _http.get(
          '$_api$_signupFormUrlPath?dataId=${Uri.encodeComponent('xsxx|&hdsq|$id')}',
          headers: _xgHeaders,
          redirect: false,
        );
      } on ApiError catch (e) {
        // 会话失效不能重试（要重新登录）；其余（连接被掐断 / 超时）退一步再试一次
        if (e.sessionLost) rethrow;
        lastError = e.message;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
      }
    }
    throw ApiError(
      '$lastError\n\n'
      '多半是学校学工系统这边临时断开了连接（与 App 无关）：'
      '过一会儿再点报名，或先用浏览器登录学工系统完成报名',
    );
  }

  /// 活动报名：先 GET 学校动态表单定义（预填值全部来自 defaultValue），原样 urlencoded 提交。
  ///
  /// 写操作：只提交一次、绝不重试（重复提交会生成多条申请记录）。
  Future<Map<String, dynamic>> signupActivity(Object id) async {
    if (!loggedIn) throw ApiError('未登录学工系统');
    final formResp = await _signupFormWithRetry(id);
    if (formResp.status >= 300 && formResp.status < 400) _sessionLost();
    final j = _parse(formResp);
    if (j is! Map) _sessionLost();
    if (j['code'] != 0) throw ApiError((j['msg'] ?? '报名表单获取失败').toString());
    final d = (j['data'] as Map?) ?? const {};
    final form = <String, String>{};
    // 字段声明也留一份（按 fieldCode 索引），用来判断哪些是必填却没值。
    final specs = <String, Map>{};
    for (final fRaw in (d['fields'] as List?) ?? const []) {
      final f = fRaw is Map ? fRaw : const {};
      final code = '${f['fieldCode'] ?? ''}';
      if (code.isEmpty || code == 'bmfj') continue; // 附件字段不参与
      final val = f['defaultValue'];
      if (code == 'hdkssj|hdjssj') {
        // 复合字段是「开始,结束」逗号拼接，提交时拆成两个
        final parts = '$val'.split(',');
        if (parts.length == 2) {
          form['hdkssj'] = parts[0].trim();
          form['hdjssj'] = parts[1].trim();
        }
        continue;
      }
      form[code] = val == null ? '' : '$val';
      specs[code] = f;
    }
    // 必填项为空就不提交：学校侧会把整张表单直接丢掉（现象是连接被 RST 或回一句表单错误），
    // 提交出去还可能留下一条无效申请。先把缺的项列给用户，让他回学工系统补资料。
    final missing = <String>[];
    specs.forEach((code, f) {
      final required =
          f['required'] == true ||
          f['isRequired'] == true ||
          f['required'] == '1';
      if (required && (form[code] ?? '').trim().isEmpty) {
        missing.add('${f['fieldName'] ?? f['title'] ?? code}');
      }
    });
    if (missing.isNotEmpty) {
      final names = missing.take(3).join('、');
      throw ApiError(
        '报名表还有 ${missing.length} 项没填：$names'
        '${missing.length > 3 ? '…' : ''}。请先到学工系统补齐个人资料后再报名',
      );
    }
    if (form.length < 10 || !form.containsKey('hdid')) {
      throw ApiError('报名表单解析失败（活动可能不存在、不在报名期或已报名）(${formResp.status})');
    }
    form['hdid'] = '$id';
    form.putIfAbsent('decisionSignature', () => '');
    final resp = await _http.postForm(
      '$_api${d['saveUrl'] ?? _signupUrlPath}',
      form,
      headers: _xgHeaders,
      redirect: false,
    );
    final r = _parse(resp);
    if (r is! Map || r['code'] != 0) {
      final msg = r is Map ? (r['msg'] ?? '').toString() : '';
      throw ApiError(msg.isNotEmpty ? msg : '报名提交失败(${resp.status})');
    }
    return {
      'instance_id': ((r['data'] as Map?)?['instanceId'] ?? '').toString(),
    };
  }
}
