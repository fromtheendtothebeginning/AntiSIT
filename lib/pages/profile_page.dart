import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../widgets/common.dart';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _statusLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  void _refreshAll() {
    if (!AppState.I.loggedIn) return;
    _loadStatus();
    _ensureStudentInfo();
  }

  Future<void> _loadStatus() async {
    setState(() => _statusLoading = true);
    try {
      final r = await ApiClient.I.status();
      AppState.I.statusInfo = r;
      AppState.I.studentInfo = null; // 状态变化后重取学籍
    } catch (_) {} // 状态获取失败不打断页面
    if (mounted) setState(() => _statusLoading = false);
    _ensureStudentInfo();
  }

  Future<void> _ensureStudentInfo() async {
    if (AppState.I.studentInfo != null) return;
    try {
      final r = await ApiClient.I.score();
      AppState.I.studentInfo = r['data']?['student'] as Map<String, dynamic>?;
      ToolCache.score = r['data'] as Map<String, dynamic>?;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _disconnectVpn() async {
    await ApiClient.I.disconnect();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已断开 VPN 隧道，下次查询会自动重连'), behavior: SnackBarBehavior.floating));
    _loadStatus();
  }

  void _goLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _exitDemoAndLogin() async {
    await AppState.I.setDemo(false);
    if (!mounted) return;
    _goLogin();
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('将清除本机登录 token 并断开 VPN 隧道，返回浏览模式（不会进入登录页）；若开启了记住密码，下次登录可一键填入。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
        ],
      ),
    );
    if (ok != true) return;
    await ApiClient.I.disconnect();
    await AppState.I.clearSession(keepCreds: AppState.I.remember);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已退出登录'), behavior: SnackBarBehavior.floating));
  }

  Future<void> _switchServer() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('服务器地址'),
        children: [
          for (final (label, url) in const [('生产环境', AppState.prodUrl), ('本地调试', AppState.localUrl)])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, url),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(label),
                subtitle: Text(url, style: const TextStyle(fontSize: 12)),
                trailing: AppState.I.serverUrl == url
                    ? const Icon(Icons.check_circle, color: SemColors.accent)
                    : null,
              ),
            ),
        ],
      ),
    );
    if (picked != null && picked != AppState.I.serverUrl) {
      await AppState.I.setServer(picked);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已切换到 $picked'), behavior: SnackBarBehavior.floating));
      }
      _refreshAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) {
        final loggedIn = st.loggedIn;
        final info = st.studentInfo;
        final status = st.statusInfo;
        final session = status?['session'] as Map<String, dynamic>?;
        final connected = session?['connected'] == true;
        final configured = status?['configured'] == true;

        return Scaffold(
          appBar: AppBar(
            title: const Text('我的'),
            actions: [
              if (loggedIn)
                IconButton(
                    onPressed: _statusLoading ? null : _refreshAll,
                    icon: const Icon(Icons.refresh),
                    tooltip: '刷新状态'),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: [
              // 头部（未登录时整卡可点，直接进登录页）
              AppCard(
                onTap: loggedIn || st.demo ? null : _goLogin,
                child: loggedIn && !st.demo
                    ? Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: SemColors.accentSoft,
                            child: Text(
                              (st.username ?? '校').characters.first.toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold,
                                  color: SemColors.accent),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(st.username ?? '-',
                                    style: const TextStyle(
                                        fontSize: 18, fontWeight: FontWeight.bold,
                                        color: SemColors.textPrimary)),
                                const SizedBox(height: 3),
                                Text('${status?['student_id_masked'] ?? '学号未配置'}',
                                    style: const TextStyle(
                                        fontSize: 13, color: SemColors.textMuted)),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          const CircleAvatar(
                            radius: 28,
                            backgroundColor: SemColors.accentSoft,
                            child: Icon(Icons.person_outline, size: 30, color: SemColors.accent),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(st.demo ? '演示模式' : '未登录',
                                    style: const TextStyle(
                                        fontSize: 18, fontWeight: FontWeight.bold,
                                        color: SemColors.textPrimary)),
                                const SizedBox(height: 8),
                                FilledButton(
                                  onPressed: st.demo
                                      ? null
                                      : () => Navigator.of(context)
                                          .push(MaterialPageRoute(builder: (_) => const LoginPage())),
                                  style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 18)),
                                  child: Text(st.demo ? '演示数据，退出后可登录' : '去登录'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 10),

              // 点击登录组件（游客 / 演示模式都提供明确入口）
              if (!loggedIn)
                AppCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.login_rounded, color: SemColors.accent),
                    title: const Text('点击登录',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        st.demo ? '退出演示模式并登录 anticraft 账号' : '登录后可查看课表导入、校园码、成绩等校园数据',
                        style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: st.demo ? _exitDemoAndLogin : _goLogin,
                  ),
                ),
              if (!loggedIn) const SizedBox(height: 10),

              if (loggedIn) ...[
                // 凭据配置引导（对应网站「我的 → 校园服务」）
                if (!configured && !st.demo)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: SemColors.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: SemColors.danger.withValues(alpha: 0.3)),
                    ),
                    child: const Text(
                      '校园凭据未配置：请登录 anticraft.top →「我的 → 校园服务」填写学号与 VPN 密码，隧道类查询才能使用。',
                      style: TextStyle(fontSize: 12.5, color: SemColors.danger, height: 1.6),
                    ),
                  ),
                if (configured && status?['auto_captcha'] != true)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: SemColors.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: SemColors.warning.withValues(alpha: 0.35)),
                    ),
                    child: const Text(
                      '未开启「AI 自动识别验证码」：请在网站「我的 → 校园服务」开启，否则隧道类查询会失败。',
                      style: TextStyle(fontSize: 12.5, color: SemColors.warning, height: 1.6),
                    ),
                  ),

                // 学籍信息
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('学籍信息', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 6),
                      if (info == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                              configured ? '打开「工具 → 二课分数」后自动获取' : '配置校园凭据后自动获取',
                              style: const TextStyle(fontSize: 12, color: SemColors.textMuted)),
                        )
                      else ...[
                        _kv('年级', '${info['nj'] ?? '-'}'),
                        _kv('学院', '${info['bmmc'] ?? '-'}'),
                        _kv('专业', '${info['zymc'] ?? '-'}'),
                        _kv('班级', '${info['bjmc'] ?? '-'}'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // 服务状态
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('服务状态', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const Spacer(),
                          if (_statusLoading)
                            const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: (connected ? SemColors.success : SemColors.warning).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: (connected ? SemColors.success : SemColors.warning)
                                        .withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                connected ? '校园网隧道已连接' : '隧道未连接（首次查询时建立）',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: connected ? SemColors.success : SemColors.warning),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          _readyChip('学工登录', status?['cas_ready'] as bool?),
                          _readyChip('教务登录', status?['jwxt_ready'] as bool?),
                          _readyChip('支付密码', status?['has_pay_password'] as bool?),
                          _readyChip('默认寝室', status?['has_dorm'] as bool?),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text('登录态失效会在下次查询时自动重登',
                          style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                      if (connected)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _disconnectVpn,
                            style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: SemColors.textSecondary),
                            child: const Text('断开 VPN', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // 设置
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: const Text('服务器地址'),
                      subtitle: Text(st.serverUrl, style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _switchServer,
                    ),
                    ListenableBuilder(
                      listenable: AppState.I,
                      builder: (_, __) => SwitchListTile(
                        secondary: const Icon(Icons.lock_outline),
                        title: const Text('记住密码并自动重登'),
                        subtitle: const Text('token 失效时无需重新输入', style: TextStyle(fontSize: 12)),
                        value: st.remember,
                        onChanged: (v) => AppState.I.setRemember(v),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (loggedIn && !st.demo)
                AppCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.logout, color: SemColors.danger),
                    title: const Text('退出登录',
                        style: TextStyle(
                            color: SemColors.danger, fontWeight: FontWeight.w600)),
                    onTap: _logout,
                  ),
                ),
              if (st.demo)
                AppCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.science_outlined, color: SemColors.accent),
                    title: const Text('退出演示模式',
                        style: TextStyle(
                            color: SemColors.accent, fontWeight: FontWeight.w600)),
                    onTap: () async {
                      await AppState.I.setDemo(false);
                    },
                  ),
                ),
              const SizedBox(height: 14),
              const Center(
                child: Text('AntiSIT · 数据来自 anticraft.top 开放接口',
                    style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _readyChip(String label, bool? ready) {
    final color = ready == true ? SemColors.success : SemColors.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ready == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(k, style: const TextStyle(fontSize: 13, color: SemColors.textMuted)),
            ),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}
