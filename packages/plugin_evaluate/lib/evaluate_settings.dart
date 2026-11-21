import 'package:campus_core/campus_core.dart';

/// 评教的账号设置：只在需要**单独账号**时用（默认复用 App 的直连凭据）。
///
/// 代理不再单独配置：直连模式自己连校园网，服务器模式走服务器给的校园隧道，
/// 两条路都由 [EvaluateApi] 自己按当前模式选。
class EvaluateSettings {
  static final EvaluateSettings I = EvaluateSettings._();
  EvaluateSettings._();

  /// 评教用的学号；空 = 用 App 直连凭据里的学号。
  String studentId = '';

  /// 评教用的教务密码；空 = 用 App 直连凭据里的统一身份认证密码。
  String password = '';

  bool loaded = false;

  String get effectiveStudentId =>
      studentId.trim().isNotEmpty ? studentId.trim() : AppState.I.creds.studentId.trim();

  String get effectivePassword =>
      password.isNotEmpty ? password : AppState.I.creds.password;

  bool get hasCredential =>
      effectiveStudentId.isNotEmpty && effectivePassword.isNotEmpty;

  /// 设置页展示用：不暴露密码，只说明「用 App 凭据 / 单独填写」。
  String get credentialSource =>
      studentId.trim().isNotEmpty ? '单独填写（' + maskStudentId(studentId) + '）' : '复用 App 的直连凭据';

  /// 当前能不能连教务：直连要看有没有凭据，服务器模式看有没有服务器地址。
  ({bool ok, String reason}) connectivity() {
    final st = AppState.I;
    if (st.demo) return (ok: false, reason: '演示模式没有真实教务数据');
    if (st.direct) {
      if (!hasCredential) {
        return (ok: false, reason: '直连模式还没填学号 / 密码：到「我的 → 连接设置」补上');
      }
      return (ok: true, reason: '直连（设备需在校园网 / 校内 VPN 内）');
    }
    if (st.serverUrl.trim().isEmpty) {
      return (ok: false, reason: '服务器模式还没填服务器地址：到「我的 → 连接设置」补上');
    }
    return (ok: true, reason: '经服务器校园隧道');
  }

  Future<void> load() async {
    loaded = true;
  }

  Future<void> save({String? studentId, String? password}) async {
    if (studentId != null) this.studentId = studentId.trim();
    if (password != null) this.password = password;
    // 走 App 的加密存储（direct_creds 同一个口袋），不落明文
    final creds = AppState.I.creds;
    await AppState.I.persistDirect();
    if (creds.studentId.isEmpty) return;
  }
}