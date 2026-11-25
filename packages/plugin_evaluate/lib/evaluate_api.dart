import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:campus_core/campus_core.dart';

import 'evaluate_model.dart';
import 'evaluate_session.dart';

/// 教务评教（正方 9.0 `xspjgl` / 功能码 `N401605`）的客户端：复用 App 已登录的教务会话。
/// 传输层特殊：教务那台 Tengine 对带 SNI 的 TLS 握手直接 reset，所以走自实现的 HTTP/1.1 + [startNoSniTls]。
class EvaluateApi {
  EvaluateApi({
    required this.session,
    this.proxyUrl = '',
    this.onLog,
  });

  /// 已就绪的教务会话（Cookie + 域名）。
  final EvaluateSession session;

  /// 服务器模式给的校园隧道 HTTP 代理（`http://host:port`）；空 = 直连。
  final String proxyUrl;

  final void Function(String line)? onLog;

  static const String _gnmkdm = 'N401605';

  String get base => session.base.replaceAll(RegExp(r'/+$'), '');

  String get _jwglxt => '$base/jwglxt';

  String get _listReferer =>
      '$_jwglxt/xspjgl/xspj_cxXspjIndex.html?doType=details&gnmkdm=$_gnmkdm&layout=default';

  void _log(String line) => onLog?.call(line);

  /// 会话是否还活着：用「不存在的功能码」探针，健康会话会把学号写进 sessionUserKey，
  /// 半失效会话那里是空串。
  Future<bool> checkSession() async {
    try {
      final r = await _request('GET',
          '$_jwglxt/xspjgl/xspj_cxXspjIndex.html?doType=details&gnmkdm=N999999&layout=default');
      final m = RegExp('id="sessionUserKey"[^>]*value="([^"]*)"').firstMatch(r.text);
      return m != null && m.group(1)!.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 已阅读须知（零门槛端点，返回 "1" 才算成功；顺便当健康探针）。
  Future<void> acknowledgeNotice() async {
    final r = await _request('POST', '$_jwglxt/xtgl/rzgl_cxAddRdrz.html', form: const {});
    final t = r.text.trim();
    if (t == '"1"' || r.json == 1 || r.json == '1') return;
    throw EvaluateError.rpc(r.status, t, hint: '登录状态失效，请重新登录');
  }

  /// 待评列表（一条 = 一位教师 × 一个教学班）。
  Future<List<EvalTarget>> fetchTargets() async {
    final r = await _request(
      'POST',
      '$_jwglxt/xspjgl/xspj_cxXspjIndex.html?doType=query&gnmkdm=$_gnmkdm',
      form: const {
        'queryModel.showCount': '200',
        'queryModel.currentPage': '1',
      },
      ajax: true,
      referer: _listReferer,
    );
    final j = r.json;
    if (j is! Map) {
      throw EvaluateError.rpc(r.status, r.text, hint: '会话已失效，请重新登录');
    }
    final items = j['items'];
    if (items is! List) return const [];
    return [
      for (final raw in items)
        if (EvalTarget.tryParse(raw) case final t?) t,
    ];
  }

  /// 评价情况汇总：待评 / 已保存 / 已提交。
  Future<EvalSummary> fetchSummary() async {
    final r = await _request('POST', '$_jwglxt/xspjgl/xspj_cxXspjqk.html',
        form: const {}, ajax: true);
    final j = r.json;
    if (j is! Map) return const EvalSummary();
    return EvalSummary(
      pending: asInt(j['wpgs']) ?? 0,
      saved: asInt(j['bcgs']) ?? 0,
      submitted: asInt(j['tjgs']) ?? 0,
    );
  }

  /// 取一节课的评分表单。
  Future<EvalForm> fetchForm(EvalTarget target) async {
    final query = {
      'jxb_id': target.jxbId,
      'kch_id': target.kchId,
      'xsdm': target.xsdm,
      'jgh_id': target.jghId,
      'tjzt': target.tjzt,
      'pjmbmcb_id': '',
      'sfcjlrjs': target.sfcjlrjs,
      'gnmkdm': _gnmkdm,
    };
    final r = await _request(
      'GET',
      '$_jwglxt/xspjgl/xspj_cxXspjDisplay.html?${Uri(queryParameters: query).query}',
      ajax: true,
      referer: '$_listReferer&offDetails=1',
    );
    if (r.status == 911) {
      throw const EvaluateError('请求被教务拒绝（911）：请重新登录后再试');
    }
    final form = EvalForm.tryParse(r.text);
    if (form == null) {
      throw const EvaluateError('没解析出评分表单：这一条可能已提交，或教务页面改版了');
    }
    return form;
  }

  /// 保存一节课的评价（可再改）。
  /// **返回值不可信**：服务端对不合法数据也会先回「保存成功！」再静默丢弃，
  /// 判据必须靠 [fetchSummary] / [fetchTargets] 复查。
  Future<String> saveForm(EvalForm form, Map<String, double> scores,
          {String comment = ''}) =>
      _write(form, scores, comment: comment, submit: false);

  /// 提交一节课的评价（**不可撤销**）。同样需要复查才算成功。
  Future<String> submitForm(EvalForm form, Map<String, double> scores,
          {String comment = ''}) =>
      _write(form, scores, comment: comment, submit: true);

  Future<String> _write(
    EvalForm form,
    Map<String, double> scores, {
    required bool submit,
    required String comment,
  }) async {
    final fields = buildSubmitFields(form, scores, comment: comment, submit: submit);
    final r = await _request(
      'POST',
      '$_jwglxt/xspjgl/xspj_${submit ? 'tj' : 'bc'}Xspj.html',
      form: fields,
      ajax: true,
      referer: _listReferer,
    );
    final text = _unwrapJsonString(r.text);
    if (text.contains('失败')) throw EvaluateError(text);
    return text;
  }

  /// 提交前那几道只读校验（同分 / 满分 / 数据异常）。返回空串表示没问题。
  Future<String> precheck(EvalForm form, double total) async {
    final savedId = form.models.isEmpty ? '' : form.models.first.savedId;
    final checks = <String, Map<String, String>>{
      '/xspjgl/xspj_cxSftf.html': {
        'bfzpf': fmtScore(total),
        'jxb_id': form.jxbId,
        'jgh_id': form.jghId,
      },
      '/xspjgl/xspj_cxInsjjg.html': const {},
      '/xspjgl/xspj_cxInmfzb.html': {'xspfb_id': savedId},
      '/xspjgl/xspj_cxInmffz.html': {
        'xspfb_id': savedId,
        'jxb_id': form.jxbId,
        'bfzpf': fmtScore(total),
      },
    };
    for (final entry in checks.entries) {
      try {
        final r =
            await _request('POST', _jwglxt + entry.key, form: entry.value, ajax: true);
        final v = r.text.trim();
        if (v.isEmpty || v == '0' || v == '"0"' || v == '""') continue;
        if (v == '1' || v == '"1"') continue;
        // 同分检查返回非 0 只是「和之前评过的一样」的提醒，不阻断
        if (entry.key.contains('cxSftf')) continue;
        final msg = _unwrapJsonString(v);
        if (msg.isNotEmpty) return msg;
      } catch (_) {
        // 校验端点失败不该挡住主流程；真正的拦截在提交那一步
      }
    }
    return '';
  }

  /// 发一次请求并跟随重定向（最多 6 跳）。
  Future<_Resp> _request(
    String method,
    String url, {
    Map<String, String>? form,
    bool followRedirect = true,
    bool ajax = false,
    String? referer,
  }) async {
    final uri = Uri.parse(url.startsWith('http') ? url : base + url);
    String? body;
    var verb = method.toUpperCase();
    if (form != null) {
      final flat = <String, String>{};
      for (final e in form.entries) {
        flat.putIfAbsent(e.key, () => e.value);
      }
      body = encodeForm(flat);
    }
    var current = uri;
    for (var hop = 0; hop < 6; hop++) {
      final resp = await _sendOnce(verb, current,
          body: body, ajax: ajax, referer: referer);
      if (!followRedirect ||
          resp.status < 300 ||
          resp.status >= 400 ||
          resp.location.isEmpty) {
        return resp;
      }
      current = current.resolve(resp.location);
      if (resp.status == 303 ||
          ((resp.status == 301 || resp.status == 302) && verb != 'GET')) {
        verb = 'GET';
        body = null;
      }
    }
    return _sendOnce(verb, current, body: body, ajax: ajax, referer: referer);
  }

  /// 建连（直连 / 校园隧道）、写请求、读完整响应，并吸收续期的 Set-Cookie。
  Future<_Resp> _sendOnce(
    String method,
    Uri uri, {
    String? body,
    bool ajax = false,
    String? referer,
  }) async {
    final host = uri.host;
    final port = uri.port == 0 ? (uri.scheme == 'https' ? 443 : 80) : uri.port;
    final socket = proxyUrl.trim().isEmpty
        ? await connectDirect(host, port)
        : await connectViaProxy(proxyUrl, host, port);
    Socket channel;
    if (uri.scheme == 'https') {
      final tls = await startNoSniTls(socket);
      final cert = tls.peerCertificate;
      if (cert != null && !verifyHost(cert, host)) {
        tls.destroy();
        throw EvaluateError('代理后面的证书不属于 $host：连接可能被劫持，已中止');
      }
      channel = tls;
    } else {
      channel = socket;
    }

    final path = uri.path.isEmpty ? '/' : uri.path;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    final headers = <String>[
      '$method $path$query HTTP/1.1',
      'Host: $host',
      'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0 Safari/537.36 AntiSIT-Eval',
      'Accept: */*',
      'Accept-Language: zh-CN,zh;q=0.9',
      'Accept-Encoding: identity',
      'Connection: close',
      if (ajax) 'X-Requested-With: XMLHttpRequest',
      if (referer != null) 'Referer: $referer',
      if (body != null)
        'Content-Type: application/x-www-form-urlencoded;charset=utf-8',
    ];
    final cookie = session.cookieHeader(host);
    if (cookie.isNotEmpty) headers.add('Cookie: $cookie');
    final bodyBytes = body == null ? null : utf8.encode(body);
    if (bodyBytes != null) headers.add('Content-Length: ${bodyBytes.length}');
    channel.add(utf8.encode('${headers.join('\r\n')}\r\n\r\n'));
    if (bodyBytes != null) channel.add(bodyBytes);
    await channel.flush();

    final bytes = await channel.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    channel.destroy();
    final resp = _Resp.parse(Uint8List.fromList(bytes));
    session.absorbCookies(host, resp.setCookies);
    _log('$method $path → ${resp.status} ${bytes.length}B');
    if (resp.status == 901) {
      throw EvaluateError.rpc(901, resp.text, hint: '登录已失效，请重新登录');
    }
    return resp;
  }

  /// 服务端返回的 "保存成功！" 是 JSON 字符串：拆掉引号与转义。
  static String _unwrapJsonString(String raw) {
    final t = raw.trim();
    if (t.length < 2) return t;
    try {
      final decoded = jsonDecode(t);
      if (decoded is String) return decoded;
    } catch (_) {}
    return t;
  }

  /// 按 application/x-www-form-urlencoded 编码（键值都做百分号编码，空格用 %20）。
  static String encodeForm(Map<String, String> fields) {
    final parts = <String>[];
    fields.forEach((k, v) {
      parts.add('${_pct(k)}=${_pct(v)}');
    });
    return parts.join('&');
  }

  static String _pct(String s) => Uri.encodeComponent(s);
}

/// 最小 HTTP/1.1 响应解析。
class _Resp {
  _Resp({required this.status, required this.headers, required this.bytes});

  final int status;
  final Map<String, List<String>> headers;
  final Uint8List bytes;

  String get text => utf8.decode(bytes, allowMalformed: true);
  String get location => headers['location']?.isEmpty ?? true ? '' : headers['location']!.first;
  List<String> get setCookies => headers['set-cookie'] ?? const [];

  Object? get json {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static _Resp parse(Uint8List all) {
    final headEnd = _indexOf(all, const <int>[13, 10, 13, 10]);
    if (headEnd < 0) {
      throw const EvaluateError('校园代理返回了不完整的响应（可能链路被中断）');
    }
    final headText = latin1.decode(Uint8List.sublistView(all, 0, headEnd), allowInvalid: true);
    final lines = headText.split('\r\n');
    final statusLine = lines.isEmpty ? '' : lines.first;
    final m = RegExp('HTTP/1\\.[01] (\\d{3})').firstMatch(statusLine);
    final status = m == null ? 0 : int.parse(m.group(1)!);
    final headers = <String, List<String>>{};
    for (final line in lines.skip(1)) {
      final at = line.indexOf(':');
      if (at <= 0) continue;
      final k = line.substring(0, at).trim().toLowerCase();
      final v = line.substring(at + 1).trim();
      (headers[k] ??= <String>[]).add(v);
    }
    var body = Uint8List.sublistView(all, headEnd + 4);
    final te = headers['transfer-encoding'] == null ? '' : headers['transfer-encoding']!.join(',');
    if (te.toLowerCase().contains('chunked')) body = _dechunk(body);
    return _Resp(status: status, headers: headers, bytes: body);
  }

  static int _indexOf(Uint8List data, List<int> pattern) {
    outer:
    for (var i = 0; i + pattern.length <= data.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  static Uint8List _dechunk(Uint8List data) {
    final out = BytesBuilder(copy: false);
    var i = 0;
    while (i < data.length) {
      final lineEnd = _indexOf(Uint8List.sublistView(data, i), const <int>[13, 10]);
      if (lineEnd < 0) break;
      final sizeText = latin1
          .decode(Uint8List.sublistView(data, i, i + lineEnd), allowInvalid: true)
          .split(';')
          .first;
      final size = int.tryParse(sizeText.trim(), radix: 16);
      if (size == null || size == 0) break;
      final start = i + lineEnd + 2;
      if (start + size > data.length) {
        out.add(Uint8List.sublistView(data, start));
        break;
      }
      out.add(Uint8List.sublistView(data, start, start + size));
      i = start + size + 2;
    }
    return out.takeBytes();
  }
}

/// 把表单 + 分数拼成提交用的扁平字段（jQuery `$.param` 风格的方括号键名）。
/// 抽成顶层函数是为了能单测：少一个隐藏字段学校就静默丢弃。
Map<String, String> buildSubmitFields(
  EvalForm form,
  Map<String, double> scores, {
  required bool submit,
  String comment = '',
  String sfbhmgc = '0',
}) {
  final missing = [
    for (final item in form.items)
      if (item.required && !scores.containsKey(item.id)) item.id,
  ];
  if (missing.isNotEmpty) {
    throw EvaluateError(
        '还有 ${missing.length} 项指标没打分，无法${submit ? '提交' : '保存'}');
  }
  final fields = <String, String>{
    'ztpjbl': form.ztpjbl,
    'jszdpjbl': form.jszdpjbl,
    'xykzpjbl': form.xykzpjbl,
    'jxb_id': form.jxbId,
    'kch_id': form.kchId,
    // 注意：用**表单里**的 jgh_id（真实教师 ID），不是列表里那个 256 位串
    'jgh_id': form.jghId,
    'xsdm': form.xsdm,
    'tjzt': submit ? '1' : '0',
    'sfbhmgc': sfbhmgc,
  };
  for (var i = 0; i < form.models.length; i++) {
    final m = form.models[i];
    final p = 'modelList[$i]';
    fields['$p.pjmbmcb_id'] = m.id;
    fields['$p.pjmbmc'] = m.name;
    fields['$p.pjdxdm'] = m.pjdxdm;
    fields['$p.fxzgf'] = m.fxzgf;
    // 评语在页面 JS 里先 encodeURIComponent 一次，再由 \$.param 编码第二次
    fields['$p.py'] = comment.isEmpty ? '' : Uri.encodeComponent(comment);
    fields['$p.xspfb_id'] = m.savedId;
    fields['$p.sfbhmgc'] = '0';
    var complete = true;
    for (var j = 0; j < m.groups.length; j++) {
      final g = m.groups[j];
      final gp = '$p.xspjList[$j]';
      fields['$gp.pjzbxm_id'] = g.id;
      for (var k = 0; k < g.items.length; k++) {
        final child = g.items[k];
        final score = scores[child.id];
        if (child.required && score == null) complete = false;
        if (score == null) continue;
        final c = '$gp.childXspjList[$k]';
        fields['$c.pjzbxm_id'] = child.id;
        fields['$c.pfdjdmb_id'] = child.gradeCodeId;
        fields['$c.zsmbmcb_id'] = child.templateCodeId;
        fields['$c.pjf'] = fmtScore(score);
      }
    }
    fields['$p.pjzt'] = complete ? '1' : '0';
  }
  return fields;
}

/// 分数写成整数（百分制），别把 95.0000000000001 这种浮点尾巴送进请求体。
String fmtScore(double v) {
  final r = v.roundToDouble();
  return (v - r).abs() < 0.001 ? r.toInt().toString() : v.toStringAsFixed(1);
}

/// 评教相关的错误（文案直接给用户看）。
class EvaluateError implements Exception {
  const EvaluateError(this.message, {this.code});

  final String message;

  /// 服务端 901 / 911 / HTTP 4xx 这类状态码。
  final int? code;

  /// 登录失效（需要重新登录）时为 true。
  bool get needsLogin => code == 901;

  factory EvaluateError.rpc(int status, String body, {String hint = ''}) {
    var text = body.trim();
    if (text.length > 400) text = '${text.substring(0, 400)}…';
    if (text.contains('无功能权限')) {
      return EvaluateError(hint.isEmpty ? '登录状态失效，请重新登录' : hint, code: status);
    }
    if (text.isEmpty) {
      return EvaluateError('教务返回 HTTP $status', code: status);
    }
    final plain = text
        .replaceAll(RegExp('<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return EvaluateError(
      hint.isEmpty ? '教务返回 HTTP $status：$plain' : hint,
      code: status,
    );
  }

  @override
  String toString() => message;
}