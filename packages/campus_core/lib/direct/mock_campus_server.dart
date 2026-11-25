/// 仅调试用的本地模拟校园服务：在 App 进程内按学校真实协议应答（release 不启用）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import 'crypto.dart';
import 'mock_captcha.dart';
import 'school.dart';
import 'sm4.dart';

part 'mock_campus_epay.dart';
part 'mock_campus_fixtures.dart';
part 'mock_campus_jwxt.dart';
part 'mock_campus_xg.dart';

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

  /// 寝室名（电费接口回显用）。
  static const String draftDormName = _draftDormName;

  /// 统一认证登录页的静态错误骨架，供回归用例复用。
  static const String casErrorSkeleton = _mockCasErrorSkeleton;

  /// 老版/静态方言的学业情况页面，供回归旧版解析回退。
  static const String debugAcademicStaticPage = _academicStaticPage;

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
}

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

/// 正方密码：RSA/PKCS#1 v1.5 解密（n/d 模幂 + 去填充），解不出原文返回空串。
/// 填充块 0x00 || 块类型 || 非零填充 || 0x00 || 明文，跳过第一段非零字节即可。
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
///
/// 明文 = 64 字符随机前缀 + 真实密码，IV 未知只毁掉第一个分组（正是被丢弃的前缀），所以解出来看尾部。
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
List<int> _key16(String salt) {
  final b = utf8.encode(salt.trim());
  if (b.length >= 16) return b.sublist(0, 16);
  return [...b, ...List<int>.filled(16 - b.length, 0)];
}

String _randomSalt() {
  const chars = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';
  final r = Random();
  return List<String>.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
}

BigInt _bigIntFromBytes(List<int> bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

List<int> _bytesFromBigInt(BigInt v) {
  final out = <int>[];
  var x = v;
  final mask = BigInt.from(0xFF);
  while (x > BigInt.zero) {
    out.insert(0, (x & mask).toInt());
    x = x >> 8;
  }
  return out;
}

/// 模拟服务的 RSA 密钥（2048 位，仅本机 mock 用）。

const String _rsaModulusB64 =
    'rJOjpMlVG5TgBhfpBg+j63HMw2S1vHBC6B5jcMEOYRfLJGtPo7QK07Z53BW/ZPQcASOJvzRAhzz8SW/Qn2ncKiyUNVA7zXrWXWK3lVN77uLj8bcIPJg3Q3Qra4dXPqYkY2OT4eIYompS51WpNdJV7RjD25ul9LO6yftfaR3gp2YrBxyWtzfICAuB4mWImOrGnJz49g6S41RvvvhEIIJ/A1fYwjrMhZHB6LYPkFsqSvW4qoUJKSw8iA4HI55MSnPIFREn72g9T+QRI3cntnJVKG9ca4T2nBXfWQ0nkBj1uEVE66g+goxaQuDiMX0kCQWQbR8ywv06s1yXYewLTZK0Xw==';
const String _rsaExponentB64 = 'AQAB';
const String _rsaPrivateB64 =
    'pR6J15QvEznJcusTsRHr4805fsZwQEElMxRITszYpjtuyYTHaTlNlq2kQNiqDLynwssu87vZ9ct7FAShFrXhypRmpfADmCHs0uMuBfkfvjxmnpJilh+J2Mdg9/xBlJbAgDv5dYmvyk5yzhae1PlP74/fbdKp4czJbpJOArRsi5zZNBIEYW12ET0iwTWp0kJfEEhrXos3mttohbaTiLWq1E6UTnb3O5faFTnf8dIb1h4rgDqyb8LlT7pc72UseA/bTFqoEamLxiKaBRGSiSf77J8LW8KAv7kt8vwLyw1jeIupqDQXSenoMWlkfe2ED+TvP7Hg8u0Vw5RuObt0ovMFEQ==';

final BigInt _rsaModulus = _bigIntFromBytes(base64Decode(_rsaModulusB64));
final BigInt _rsaPrivate = _bigIntFromBytes(base64Decode(_rsaPrivateB64));

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
