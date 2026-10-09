import 'dart:convert';

/// 学校档案：直连模式下 App 直接访问的校园系统地址。
/// 默认值对照 index 后端 campus/config.py（默认上海应用技术大学 SIT，迁移他校改这里）。
class SchoolProfile {
  SchoolProfile({
    required this.name,
    required this.authBase,
    required this.jwxtBase,
    required this.xgBase,
    required this.ecardBase,
    this.dektAesKey = '',
  });

  String name;
  String authBase; // 统一身份认证 authserver（含 /authserver 路径）
  String jwxtBase; // 教务（正方）
  String xgBase; // 学工（第二课堂）
  String ecardBase; // 校付宝（校园码/电费）
  String dektAesKey; // isEncrypt 响应解密密钥，留空表示不加密（SIT 默认未启用）

  static SchoolProfile sit() => SchoolProfile(
        name: '上海应用技术大学',
        authBase: 'https://authserver.sit.edu.cn/authserver',
        jwxtBase: 'https://jwxt.sit.edu.cn',
        xgBase: 'https://xg.sit.edu.cn',
        ecardBase: 'https://ecard.sit.edu.cn',
      );

  bool get isComplete =>
      authBase.isNotEmpty && jwxtBase.isNotEmpty && xgBase.isNotEmpty && ecardBase.isNotEmpty;

  /// 快速填写：按学校域名推导各系统地址（正方/金智最常见的「子系统前缀.学校域名」形态）。
  static SchoolProfile fromDomain(String domain) {
    final d = domain
        .trim()
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/+$'), '');
    final host = d.isEmpty ? 'sit.edu.cn' : d;
    return SchoolProfile(
      name: host,
      authBase: 'https://authserver.$host/authserver',
      jwxtBase: 'https://jwxt.$host',
      xgBase: 'https://xg.$host',
      ecardBase: 'https://ecard.$host',
    );
  }

  SchoolProfile clone() => SchoolProfile(
        name: name,
        authBase: authBase,
        jwxtBase: jwxtBase,
        xgBase: xgBase,
        ecardBase: ecardBase,
        dektAesKey: dektAesKey,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'authBase': authBase,
        'jwxtBase': jwxtBase,
        'xgBase': xgBase,
        'ecardBase': ecardBase,
        'dektAesKey': dektAesKey,
      };

  static SchoolProfile fromJson(Map<String, dynamic> j) => SchoolProfile(
        name: (j['name'] ?? '').toString(),
        authBase: (j['authBase'] ?? '').toString(),
        jwxtBase: (j['jwxtBase'] ?? '').toString(),
        xgBase: (j['xgBase'] ?? '').toString(),
        ecardBase: (j['ecardBase'] ?? '').toString(),
        dektAesKey: (j['dektAesKey'] ?? '').toString(),
      );

  static String encodeList(List<SchoolProfile> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<SchoolProfile> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final arr = jsonDecode(raw);
      if (arr is List) {
        return arr
            .whereType<Map>()
            .map((e) => SchoolProfile.fromJson(e.cast<String, dynamic>()))
            .where((e) => e.name.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [];
  }
}

/// 直连模式的校园凭据（学号 / 统一身份认证密码 / 校付宝支付密码 / 寝室 / 姓名）。
/// 明文存本机（与「记住密码」同一安全级别），仅用于本机直连学校系统。
class CampusCreds {
  String studentId = '';
  String password = ''; // 统一身份认证密码（= VPN 密码）
  String payPassword = ''; // 校付宝支付密码
  String dorm = ''; // 如「24号楼1016」
  String realName = ''; // 校付宝登录需真实姓名；空则查学工自动补全

  bool get hasLogin => studentId.trim().isNotEmpty && password.isNotEmpty;
  bool get hasPay => payPassword.isNotEmpty;
  bool get hasDorm => dorm.trim().isNotEmpty;

  void clearSession() {
    // 凭据保留，仅清空会话（token/会话由 CampusDirect 持有）
  }

  Map<String, dynamic> toJson() => {
        'studentId': studentId,
        'password': password,
        'payPassword': payPassword,
        'dorm': dorm,
        'realName': realName,
      };

  static CampusCreds fromJson(Map<String, dynamic>? j) {
    final c = CampusCreds();
    if (j == null) return c;
    c.studentId = (j['studentId'] ?? '').toString();
    c.password = (j['password'] ?? '').toString();
    c.payPassword = (j['payPassword'] ?? '').toString();
    c.dorm = (j['dorm'] ?? '').toString();
    c.realName = (j['realName'] ?? '').toString();
    return c;
  }
}

/// 学号打码（与服务器模式 status 的 student_id_masked 同风格）。
String maskStudentId(String sid) {
  final s = sid.trim();
  if (s.length <= 4) return s.isEmpty ? '' : '****';
  return '${s.substring(0, 3)}****${s.substring(s.length - 2)}';
}
