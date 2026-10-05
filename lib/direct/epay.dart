import '../api_error.dart';
import 'http_session.dart';
import 'sm4.dart';

/// 寝室字符串 → 楼号/房间号。接口 buildid = 楼号 + 1（24 号楼 → 25）。
/// 支持「24号楼1016」「24-1016」「奉贤校区 24 号楼 1016」等。
({int building, int room, int buildid, int roomid}) parseDorm(String dormStr) {
  final m = RegExp(r'(\d+)\s*号?\s*楼?\s*[-]?\s*(\d+)').firstMatch(dormStr.trim());
  if (m == null) {
    throw ApiError('无法解析寝室号「$dormStr」，请按「24号楼1016」格式填写');
  }
  final building = int.parse(m.group(1)!);
  final room = int.parse(m.group(2)!);
  return (building: building, room: room, buildid: building + 1, roomid: room);
}

/// 校付宝（epeortal / openservice）客户端：校园码、电费查询/充值、校园卡余额。
/// 公网可达：不需要校园网/VPN，也不需要验证码；支付密码用 SM4 加密提交。
/// 移植自 index 后端 campus/electricity.py 与 campus/ecard.py。
class EpayClient {
  EpayClient(String base) : base = base.replaceAll(RegExp(r'/+$'), '') {
    _http = HttpSession(
      trustHosts: [Uri.parse(this.base).host],
      persistKey: 'direct_cookies_epay',
    );
  }

  final String base;
  static const int _elcsysid = 2;
  static const String _areaid = '99';

  late final HttpSession _http;
  String? _token;

  Uri _u(String path) => Uri.parse('$base/openservice$path');

  /// 可达性探测（连接设置页「测试连接」）：校付宝公网可达，无需校园网。
  Future<String?> probe() async {
    final r = await _http.get('$base/epeortal/pages/h5/elecCharge');
    if (r.status >= 400) throw ApiError('校付宝返回 HTTP ${r.status}，请核对该校校付宝域名');
    return '可达（公网直连，无需校园网）';
  }

  Map<String, String> get _headers => {
        'Referer': '$base/epeortal/pages/h5/elecCharge',
        'Origin': base,
        'sw-Authorization': 'Bearer ${_token ?? ''}',
      };

  void dispose() => _http.dispose();

  /// 登录换 accessToken：custname 必须是真实姓名（用学号会被拒）。
  Future<void> _login(String studentId, String realName, String payPassword) async {
    if (studentId.isEmpty) throw ApiError('缺少学号，请在连接设置里填写校园凭据');
    if (realName.isEmpty) throw ApiError('缺少姓名：校付宝登录需要真实姓名，请在连接设置里填写');
    if (payPassword.isEmpty) throw ApiError('缺少校付宝支付密码，请在连接设置里填写');
    final resp = await _http.postJson(_u('/epeortalAuth/login').toString(), {
      'custname': realName,
      'pwd': sm4Encrypt(payPassword),
      'stuempno': studentId,
    });
    final obj = resp.json;
    if (obj is! Map) throw ApiError('校付宝系统返回异常（HTTP ${resp.status}）');
    if ('${obj['retcode']}' != '0') {
      final msg = (obj['retmsg'] ?? '').toString();
      throw ApiError(msg.isEmpty ? '校付宝自动登录失败（姓名或支付密码错误）' : msg);
    }
    final token = ((obj['data'] as Map?)?['token'] ?? '').toString();
    if (token.isEmpty) throw ApiError('校付宝自动登录未返回令牌');
    _token = token;
  }

  /// 带 token 的 openservice 调用；403（令牌过期）重登续期后重试一次。
  Future<Map<String, dynamic>> _osPost(
    String path,
    Map<String, dynamic> body,
    String studentId,
    String realName,
    String payPassword,
  ) async {
    if (_token == null) await _login(studentId, realName, payPassword);
    var resp = await _http.postJson(_u(path).toString(), body, headers: _headers);
    if (resp.status == 403) {
      _token = null;
      await _login(studentId, realName, payPassword);
      resp = await _http.postJson(_u(path).toString(), body, headers: _headers);
    }
    final obj = resp.json;
    if (obj is! Map) throw ApiError('校园卡系统返回异常（HTTP ${resp.status}）');
    if ('${obj['retcode']}' != '0') {
      final msg = (obj['retmsg'] ?? '').toString();
      throw ApiError(msg.isEmpty ? '校付宝接口调用失败' : msg);
    }
    return ((obj['data'] as Map?) ?? const {}).cast<String, dynamic>();
  }

  /// 校园卡（一卡通钱包）余额；失败返回 null（余额不是主数据）。
  Future<double?> cardBalance(String studentId, String realName, String payPassword) async {
    try {
      final data = await _osPost('/miniprogram/wxlayout', {}, studentId, realName, payPassword);
      final layout = (data['layout'] as Map?) ?? const {};
      final parts = ((layout['balancePart'] as Map?)?['content']) as List?;
      if (parts == null || parts.isEmpty) return null;
      final n = (parts.first as Map?)?['number'];
      if (n == null) return null;
      final v = double.tryParse(n.toString());
      return v == null ? null : double.parse(v.toStringAsFixed(2));
    } catch (_) {
      return null;
    }
  }

  /// 宿舍电费余额 + 校园卡余额。restElecDegree 实为电费余额（元）。
  Future<Map<String, dynamic>> queryElectricity(
    String studentId,
    String realName,
    String payPassword,
    String dormStr,
  ) async {
    final dorm = parseDorm(dormStr);
    final data = await _osPost('/miniprogram/queryroominfo', {
      'elcsysid': _elcsysid,
      'areaid': _areaid,
      'buildid': '${dorm.buildid}',
      'roomid': '${dorm.roomid}',
    }, studentId, realName, payPassword);
    final raw = data['restElecDegree'];
    final balance = raw == null ? null : double.tryParse(raw.toString());
    return {
      'balance': balance == null ? null : double.parse(balance.toStringAsFixed(2)),
      'card_balance': await cardBalance(studentId, realName, payPassword),
      'remain': null, // 接口不返回度数
      'dorm': (data['roomName'] ?? '${dorm.building}号楼${dorm.room}').toString(),
    };
  }

  /// 缴纳电费：buyelectrityinit 创建订单 → balancepay 余额支付。amount 单位元。
  /// ⚠️ 扣款链路：调用方绝不自动重试。
  Future<Map<String, dynamic>> rechargeElectricity(
    String studentId,
    String realName,
    String payPassword,
    String dormStr,
    double amount,
  ) async {
    final dorm = parseDorm(dormStr);
    final amountFen = (amount * 100).round();
    if (amountFen <= 0) throw ApiError('充值金额必须大于 0');
    final room = {
      'elcsysid': _elcsysid,
      'areaid': _areaid,
      'roomid': '${dorm.roomid}',
      'buildid': '${dorm.buildid}',
      'roomname': '${dorm.building}号楼${dorm.room}',
    };
    final init = await _osPost('/miniprogram/buyelectrityinit',
        {...room, 'amount': amountFen}, studentId, realName, payPassword);
    final billno = (init['billno'] ?? '').toString();
    if (billno.isEmpty) throw ApiError('创建电费订单失败，未返回订单号');
    final data = await _osPost('/miniprogram/balancepay',
        {...room, 'amount': amountFen, 'billno': billno, 'pwd': ''}, studentId, realName, payPassword);
    final bal = data['balance'];
    return {
      'ok': true,
      'message': (data['retmsg'] ?? '充值成功').toString(),
      'balance': bal == null ? null : double.parse((double.parse(bal.toString()) / 100).toStringAsFixed(2)),
      'billno': billno,
      'amount': amountFen / 100,
    };
  }

  /// 校园码（离线消费码）码值——二维码由 App 渲染。
  Future<Map<String, dynamic>> qrcode(
    String studentId,
    String realName,
    String payPassword,
  ) async {
    final data = await _osPost('/miniprogram/offline', {}, studentId, realName, payPassword);
    final code = (data['qrcode'] ?? '').toString();
    if (code.isEmpty) throw ApiError('校付宝未返回校园码');
    return {'code': code};
  }
}
