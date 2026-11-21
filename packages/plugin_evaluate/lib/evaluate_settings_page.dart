import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'evaluate_settings.dart';

/// 评教设置：当前连接方式 + 可选的自填账号。
///
/// **不再有代理设置**：直连模式自己连校园网，服务器模式走服务器给的校园隧道，
/// 两种情况都按 App 当前模式自动选，用户不用填任何地址。
class EvaluateSettingsPage extends StatefulWidget {
  const EvaluateSettingsPage({super.key});

  @override
  State<EvaluateSettingsPage> createState() => _EvaluateSettingsPageState();
}

class _EvaluateSettingsPageState extends State<EvaluateSettingsPage> {
  final _studentId = TextEditingController();
  final _password = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = EvaluateSettings.I;
    _studentId.text = s.studentId;
    _password.text = s.password;
  }

  @override
  void dispose() {
    _studentId.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await EvaluateSettings.I.save(
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
    final conn = s.connectivity();
    final st = AppState.I;
    return Scaffold(
      appBar: AppBar(title: const Text('评教设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('连接方式',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Capsule(st.direct ? '直连' : '服务器模式', color: SemColors.accent),
                  ],
                ),
                const SizedBox(height: 10),
                Text(conn.reason,
                    style: TextStyle(fontSize: 12.5, height: 1.7, color: SemColors.textSecondary)),
                const SizedBox(height: 6),
                Text(
                  st.direct
                      ? '直连模式：App 用本机凭据直接访问教务，需要设备在校园网 / 校内 VPN 内。'
                      : '服务器模式：经服务器已连好的校园隧道访问教务，不用设备在校园网内。',
                  style: TextStyle(fontSize: 11.5, height: 1.6, color: SemColors.textMuted),
                ),
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
            '教务系统只能在学校内网访问：直连模式靠设备自己在校园网 / 校内 VPN，服务器模式靠服务器的校园隧道。',
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
                : const Text('保存'),
          ),
        ),
      ),
    );
  }
}