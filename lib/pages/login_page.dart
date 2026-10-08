import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../pages/home_page.dart';
import '../widgets/common.dart';
import 'connect_page.dart';

/// 登录页：**两种接入方式二选一**。
/// - 直连模式（首选）：App 用校园凭据（学号 + 统一身份认证密码）直接连学校系统，需校园网/校内 VPN；
/// - 服务器模式：填服务器域名或 IP，登录该服务器上的 anticraft 账号，由服务器代连校园内网。
/// 不强制登录：可「先逛逛」进入游客模式。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.initialError});

  final String? initialError;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();

  // 服务器模式
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pwd = TextEditingController();

  // 直连模式
  final _sid = TextEditingController();
  final _campusPwd = TextEditingController();

  late int _mode; // 0=直连（首选） 1=服务器
  bool _busy = false;
  bool _hidePwd = true;
  bool _hideCampusPwd = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final st = AppState.I;
    // 首选直连：已配过服务器地址（说明是服务器模式的老用户）时默认停在服务器页
    _mode = st.direct || st.serverUrl.isEmpty ? 0 : 1;
    _server.text = st.serverUrl;
    _user.text = st.username ?? '';
    _pwd.text = st.password ?? '';
    _sid.text = st.creds.studentId;
    _campusPwd.text = st.creds.password;
    _error = widget.initialError;
  }

  @override
  void dispose() {
    for (final c in [_server, _user, _pwd, _sid, _campusPwd]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 直连模式：存校园凭据 → 切到直连 → 用凭据探一次（失败会抛，方便立刻发现填错）。
  Future<void> _loginDirect() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final st = AppState.I;
    try {
      st.creds
        ..studentId = _sid.text.trim()
        ..password = _campusPwd.text;
      await st.persistDirect();
      await st.setMode(AppMode.direct);
      st.statusInfo = null;
      st.studentInfo = null;
      await ApiClient.I.status();
      if (!mounted) return;
      _goHome();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ApiError ? e.message : e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 服务器模式：存地址 → 切到服务器模式 → 登录该服务器上的 anticraft 账号换 JWT。
  Future<void> _loginServer() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final st = AppState.I;
    try {
      final url = AppState.normalizeServer(_server.text);
      if (url.isEmpty) throw ApiError('请填写服务器域名或 IP');
      await st.setServer(url);
      await st.setMode(AppMode.server);
      st.statusInfo = null;
      st.studentInfo = null;
      final r = await ApiClient.I.login(_user.text.trim(), _pwd.text);
      final token = r['access_token'];
      if (token is! String || token.isEmpty) {
        throw ApiError('登录响应异常：未获取到 token');
      }
      await st.saveLogin(
        token: token,
        username: _user.text.trim(),
        password: st.remember ? _pwd.text : null,
      );
      if (!mounted) return;
      _goHome();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ApiError ? e.message : e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  Future<void> _guest() async => _goHome();

  Future<void> _demo() async {
    await AppState.I.setDemo(true);
    if (!mounted) return;
    _goHome();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    final direct = _mode == 0;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Image.asset('assets/sit-mark.png',
                          width: 76,
                          height: 76,
                          // 测试环境拿不到 asset，缺图不该让整页报错
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.school_outlined, size: 64)),
                    ),
                    const SizedBox(height: 10),
                    Text('AntiSIT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: SemColors.textPrimary)),
                    const SizedBox(height: 6),
                    Text(
                      direct ? '直连校园系统 · 手机直连，经校园网访问' : '服务器代连 · 登录服务器上的账号',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: SemColors.textSecondary),
                    ),
                    const SizedBox(height: 18),

                    // 接入方式二选一（默认直连）
                    GlassTabs(
                      labels: const ['直连模式', '服务器模式'],
                      index: _mode,
                      onChanged: (i) => setState(() {
                        _mode = i;
                        _error = null;
                      }),
                    ),
                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: SemColors.accentSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: SemColors.accent.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        direct
                            ? '用学号和统一身份认证密码直接连学校系统（教务 / 学工 / 校付宝），'
                                '需手机处于校园网或校内 VPN；凭据只存本机。'
                            : '填写服务器域名或 IP，登录该服务器上的 anticraft 账号；'
                                '校园凭据在服务器端配置，服务器会代为连接校园内网。',
                        style: TextStyle(
                            fontSize: 12, color: SemColors.textSecondary, height: 1.6),
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (direct) ..._directFields(st) else ..._serverFields(),

                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: SemColors.dangerSoft,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: SemColors.danger.withValues(alpha: 0.3)),
                        ),
                        child: Text(_error!,
                            style: TextStyle(
                                fontSize: 13, color: SemColors.danger, height: 1.5)),
                      ),
                      const SizedBox(height: 8),
                    ],

                    const SizedBox(height: 6),
                    FilledButton(
                      onPressed: _busy ? null : (direct ? _loginDirect : _loginServer),
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: Colors.white))
                          : Text(direct ? '直连并进入' : '登 录',
                              style: const TextStyle(fontSize: 15)),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: ListenableBuilder(
                            listenable: AppState.I,
                            builder: (_, __) => CheckboxListTile(
                              value: AppState.I.remember,
                              onChanged: (v) => AppState.I.setRemember(v ?? true),
                              title: const Text('记住密码，掉线自动重登',
                                  style: TextStyle(fontSize: 13)),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: _busy ? null : _guest,
                            child: const Text('先逛逛（免登录）', style: TextStyle(fontSize: 13)),
                          ),
                        ),
                        SizedBox(
                            width: 1, height: 18, child: ColoredBox(color: SemColors.border)),
                        Expanded(
                          child: TextButton(
                            onPressed: _busy
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const ConnectPage())),
                            child: const Text('更多设置', style: TextStyle(fontSize: 13)),
                          ),
                        ),
                        if (kDebugMode) ...[
                          SizedBox(
                              width: 1, height: 18, child: ColoredBox(color: SemColors.border)),
                          Expanded(
                            child: TextButton(
                              onPressed: _busy ? null : _demo,
                              child: const Text('演示模式', style: TextStyle(fontSize: 13)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 直连模式字段：学校（可切换已存档案）+ 学号 + 统一身份认证密码。
  List<Widget> _directFields(AppState st) {
    final schools = st.schools.isEmpty ? [st.school] : st.schools;
    return [
      DropdownButtonFormField<String>(
        initialValue: schools.any((s) => s.name == st.school.name) ? st.school.name : schools.first.name,
        decoration: const InputDecoration(labelText: '学校', isDense: true),
        items: [
          for (final s in schools)
            DropdownMenuItem(value: s.name, child: Text(s.name)),
        ],
        onChanged: schools.length <= 1
            ? null
            : (v) {
                final s = schools.firstWhere((e) => e.name == v);
                st.setSchool(s);
                setState(() {});
              },
      ),
      const SizedBox(height: 4),
      Text('只有一所学校档案；如需增改（教务/学工等系统地址）请点下方「更多设置」。',
          style: TextStyle(fontSize: 11, color: SemColors.textMuted, height: 1.5)),
      const SizedBox(height: 12),
      GlassField(
        label: '学号',
        controller: _sid,
        prefixIcon: const Icon(Icons.badge_outlined),
        validator: (v) => (v == null || v.trim().isEmpty) ? '请输入学号' : null,
      ),
      const SizedBox(height: 14),
      GlassField(
        label: '统一身份认证密码（= 校园网 / VPN 密码）',
        controller: _campusPwd,
        obscureText: _hideCampusPwd,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _hideCampusPwd = !_hideCampusPwd),
          icon: Icon(_hideCampusPwd ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        ),
        validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
        onSubmitted: (_) => _busy ? null : _loginDirect(),
      ),
    ];
  }

  /// 服务器模式字段：服务器地址（域名或 IP）+ 账号 + 密码。
  List<Widget> _serverFields() => [
        GlassField(
          label: '服务器地址（域名或 IP，可带端口）',
          controller: _server,
          hintText: '如 anticraft.top 或 192.168.1.10:8000',
          prefixIcon: const Icon(Icons.dns_outlined),
          validator: (v) {
            final url = AppState.normalizeServer(v ?? '');
            if (url.isEmpty) return '请输入服务器域名或 IP';
            return Uri.tryParse(url)?.host.isEmpty ?? true ? '地址格式不正确' : null;
          },
        ),
        const SizedBox(height: 14),
        GlassField(
          label: '用户名',
          controller: _user,
          autofillHints: const [AutofillHints.username],
          prefixIcon: const Icon(Icons.person_outline),
          validator: (v) => (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
        ),
        const SizedBox(height: 14),
        GlassField(
          label: '密码',
          controller: _pwd,
          obscureText: _hidePwd,
          autofillHints: const [AutofillHints.password],
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            onPressed: () => setState(() => _hidePwd = !_hidePwd),
            icon: Icon(_hidePwd ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          ),
          validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
          onSubmitted: (_) => _busy ? null : _loginServer(),
        ),
      ];
}
