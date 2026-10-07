import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../pages/home_page.dart';
import '../widgets/common.dart';

/// 登录页：anticraft 账号 + 密码换 JWT。校园凭据在网站配置，App 不经手校园密码。
/// 不强制登录：可「先逛逛」进入游客模式。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.initialError});

  final String? initialError;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pwd = TextEditingController();

  bool _busy = false;
  bool _hidePwd = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final st = AppState.I;
    _user.text = st.username ?? '';
    _pwd.text = st.password ?? '';
    _error = widget.initialError;
  }

  @override
  void dispose() {
    _user.dispose();
    _pwd.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final st = AppState.I;
    try {
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
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ApiError ? e.message : e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guest() async {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  Future<void> _demo() async {
    await AppState.I.setDemo(true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      child: Image.asset('assets/sit-mark.png', width: 76, height: 76),
                    ),
                    const SizedBox(height: 10),
                    Text('AntiSIT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.bold,
                            color: SemColors.textPrimary)),
                    const SizedBox(height: 6),
                    Text(
                      '服务器账号登录 · 服务器代连校园内网',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: SemColors.textSecondary),
                    ),
                    const SizedBox(height: 24),

                    // 凭据引导条（同网站提示文案）
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: SemColors.accentSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: SemColors.accent.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        '校园凭据（学号 / VPN 密码 / 支付密码 / 寝室）只需在网站「我的 → 校园服务」配置一次，App 不需要填写校园密码。',
                        style: TextStyle(fontSize: 12, color: SemColors.textSecondary, height: 1.6),
                      ),
                    ),
                    const SizedBox(height: 16),

                    GlassField(
                      label: '用户名',
                      controller: _user,
                      autofillHints: const [AutofillHints.username],
                      prefixIcon: const Icon(Icons.person_outline),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
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
                        icon: Icon(_hidePwd
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
                      onSubmitted: (_) => _busy ? null : _login(),
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

                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _busy ? null : _login,
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _busy
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: Colors.white))
                          : const Text('登 录', style: TextStyle(fontSize: 15)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: _busy ? null : _guest,
                            child: const Text('先逛逛（免登录）', style: TextStyle(fontSize: 13)),
                          ),
                        ),
                        if (kDebugMode) ...[
                          SizedBox(
                              width: 1, height: 18, child: ColoredBox(color: SemColors.border)),
                          Expanded(
                            child: TextButton(
                              onPressed: _busy ? null : _demo,
                              child: const Text('演示模式（假数据）', style: TextStyle(fontSize: 13)),
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
}
