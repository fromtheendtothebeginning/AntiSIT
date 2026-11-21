import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'evaluate_settings.dart';

/// 评教设置：校园代理（SOCKS5）与账号。
///
/// 代理凭据是本机内部使用的，**不写进仓库、也不随构建分发**：这里填一次就存进
/// 加密存储（Android Keystore / iOS Keychain）。
class EvaluateSettingsPage extends StatefulWidget {
  const EvaluateSettingsPage({super.key});

  @override
  State<EvaluateSettingsPage> createState() => _EvaluateSettingsPageState();
}

class _EvaluateSettingsPageState extends State<EvaluateSettingsPage> {
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _studentId = TextEditingController();
  final _password = TextEditingController();
  bool _saving = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final s = EvaluateSettings.I;
    _host.text = s.proxy.host;
    _port.text = s.proxy.port > 0 ? s.proxy.port.toString() : '';
    _user.text = s.proxy.username;
    _pass.text = s.proxy.password;
    _studentId.text = s.studentId;
    _password.text = s.password;
  }

  @override
  void dispose() {
    for (final c in [_host, _port, _user, _pass, _studentId, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 0;
    if (host.isEmpty || port <= 0) {
      showErr(context, '校园代理地址和端口都要填（形如 代理域名:端口）', title: '填错了');
      return;
    }
    setState(() => _saving = true);
    try {
      await EvaluateSettings.I.save(
        proxy: SocksProxy(
          host: host,
          port: port,
          username: _user.text.trim(),
          password: _pass.text,
        ),
        studentId: _studentId.text,
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showErr(context, e, title: '保存失败');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = EvaluateSettings.I;
    return Scaffold(
      appBar: AppBar(title: const Text('评教设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('校园代理（SOCKS5）',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                GlassField(
                  label: '地址',
                  controller: _host,
                  hintText: '校内代理域名或 IP',
                  prefixIcon: const Icon(Icons.dns_outlined, size: 18),
                ),
                const SizedBox(height: 12),
                GlassField(
                  label: '端口',
                  controller: _port,
                  keyboardType: TextInputType.number,
                  hintText: '例如 10003',
                ),
                const SizedBox(height: 12),
                GlassField(
                  label: '账号（代理要求认证时填）',
                  controller: _user,
                  prefixIcon: const Icon(Icons.person_outline, size: 18),
                ),
                const SizedBox(height: 12),
                GlassField(
                  label: '密码',
                  controller: _pass,
                  obscureText: _obscure,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 18),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                const SizedBox(height: 8),
                Text('代理只存在本机的加密存储里，不会写进仓库或随 App 分发。',
                    style: TextStyle(fontSize: 11, height: 1.6, color: SemColors.textMuted)),
              ],
            ),
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('教务账号',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('留空就复用「连接设置」里 App 的直连凭据（当前：' + s.credentialSource + '）。',
                    style: TextStyle(fontSize: 11.5, height: 1.6, color: SemColors.textMuted)),
                const SizedBox(height: 12),
                GlassField(
                  label: '学号（留空复用）',
                  controller: _studentId,
                  prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                ),
                const SizedBox(height: 12),
                GlassField(
                  label: '教务密码（留空复用）',
                  controller: _password,
                  obscureText: true,
                  hintText: '不一定等于统一身份认证密码',
                ),
              ],
            ),
          ),
          PageNotes(lines: const [
            '教务系统只能在学校内网访问，校外必须经校园代理；代理不通时评教页会直接提示。',
            '这里不保存任何分数：评教记录只在教务系统里。',
          ]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存设置'),
          ),
        ),
      ),
    );
  }
}