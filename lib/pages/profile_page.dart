import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../class_reminder_service.dart';
import '../widgets/common.dart';
import 'connect_page.dart';
import 'feedback_page.dart';
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
    final direct = AppState.I.direct;
    await ApiClient.I.disconnect();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(direct ? '已清除直连会话，下次查询会重新登录学校系统' : '已断开 VPN 隧道，下次查询会自动重连'),
        behavior: SnackBarBehavior.floating));
    _loadStatus();
  }

  void _goLogin() {
    // 登录页里可选直连 / 服务器两种方式，所以不再按当前模式分流到连接设置
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
    final direct = AppState.I.direct;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: Text(direct
            ? '将清除本机保存的校园密码并断开学校系统会话，返回浏览模式（不会进入登录页）；学校信息与学号保留，'
                '再次查询时重新登录。'
            : '将清除本机登录 token 并断开 VPN 隧道，返回浏览模式（不会进入登录页）；若开启了记住密码，下次登录可一键填入。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
        ],
      ),
    );
    if (ok != true) return;
    await ApiClient.I.disconnect();
    if (direct) {
      await AppState.I.clearDirectSession();
    } else {
      await AppState.I.clearSession(keepCreds: AppState.I.remember);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已退出登录'), behavior: SnackBarBehavior.floating));
  }

  Future<void> _openConnect() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnectPage()));
    if (!mounted) return;
    _refreshAll();
    setState(() {});
  }

  /// 上课提醒开关：打开时申请通知权限（必要时再要精确闹钟权限），并按当前课表排期。
  Future<void> _onReminderToggle(bool v) async {
    final messenger = ScaffoldMessenger.of(context);
    String? tip;
    if (v) {
      tip = await ClassReminderService.I.enable();
    } else {
      await ClassReminderService.I.disable();
      tip = '已关闭上课提醒';
    }
    if (!mounted) return;
    if (tip != null) {
      messenger.showSnackBar(SnackBar(content: Text(tip), behavior: SnackBarBehavior.floating));
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
                              (st.direct ? st.school.name : (st.username ?? '校'))
                                  .characters
                                  .first
                                  .toUpperCase(),
                              style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold,
                                  color: SemColors.accent),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(st.direct ? '直连模式 · ${st.school.name}' : (st.username ?? '-'),
                                    style: TextStyle(
                                        fontSize: 18, fontWeight: FontWeight.bold,
                                        color: SemColors.textPrimary)),
                                const SizedBox(height: 3),
                                Text('${status?['student_id_masked'] ?? '学号未配置'}',
                                    style: TextStyle(
                                        fontSize: 13, color: SemColors.textMuted)),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: SemColors.accentSoft,
                            child: Icon(Icons.person_outline, size: 30, color: SemColors.accent),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(st.demo ? '演示模式' : (st.direct ? '未填写校园凭据' : '未登录'),
                                    style: TextStyle(
                                        fontSize: 18, fontWeight: FontWeight.bold,
                                        color: SemColors.textPrimary)),
                                const SizedBox(height: 8),
                                FilledButton(
                                  onPressed: st.demo
                                      ? null
                                      : () => Navigator.of(context).push(MaterialPageRoute(
                                          builder: (_) => const LoginPage())),
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
                    leading: Icon(Icons.login_rounded, color: SemColors.accent),
                    title: Text(st.direct ? '点击填写校园凭据' : '点击登录',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        st.demo
                            ? (st.direct ? '退出演示模式并填写校园凭据' : '退出演示模式并登录服务器账号')
                            : (st.direct
                                ? '填写学号与统一身份认证密码后可直接查询校园数据（需校园网）'
                                : '登录后可查看课表导入、校园码、成绩等校园数据'),
                        style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: st.demo ? _exitDemoAndLogin : _goLogin,
                  ),
                ),
              if (!loggedIn) const SizedBox(height: 10),

              if (loggedIn) ...[
                // 凭据配置引导（服务器模式对应网站「我的 → 校园服务」）
                if (!configured && !st.demo)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: SemColors.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: SemColors.danger.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      st.direct
                          ? '校园凭据未填写完整：请在「连接设置 → 直连模式」填写学号与统一身份认证密码，才能查询校园数据。'
                          : '校园凭据未配置：请登录所用服务器的网站 →「我的 → 校园服务」填写学号与 VPN 密码，隧道类查询才能使用。',
                      style: TextStyle(fontSize: 12.5, color: SemColors.danger, height: 1.6),
                    ),
                  ),
                if (configured && status?['auto_captcha'] != true && !st.direct)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: SemColors.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: SemColors.warning.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      '未开启「AI 自动识别验证码」：隧道类查询会弹出手动验证码输入框；'
                      '想让 AI 自动过码请到网站「我的 → 校园服务」开启。',
                      style: TextStyle(fontSize: 12.5, color: SemColors.warning, height: 1.6),
                    ),
                  ),
                if (st.direct)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: SemColors.accentSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: SemColors.accent.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '直连模式：数据由本机直接访问学校系统，不走任何服务器，需要在校园网 / 校内 VPN 内；登录验证码手动输入。',
                      style: TextStyle(fontSize: 12.5, color: SemColors.textSecondary, height: 1.6),
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
                              style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
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
                                st.direct
                                    ? '本机直连学校系统'
                                    : (connected ? '校园网隧道已连接' : '隧道未连接（首次查询时建立）'),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: (st.direct || connected)
                                        ? SemColors.success
                                        : SemColors.warning),
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
                      Text(
                          st.direct
                              ? '登录态失效会在下次查询时重新登录（需输入验证码）'
                              : '登录态失效会在下次查询时自动重登',
                          style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                      if (connected || st.direct)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _disconnectVpn,
                            style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: SemColors.textSecondary),
                            child: Text(st.direct ? '清除直连会话' : '断开 VPN',
                                style: const TextStyle(fontSize: 12)),
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
                      title: const Text('连接设置'),
                      subtitle: Text(
                          st.direct
                              ? '直连模式 · ${st.school.name}（本机访问学校系统）'
                              : (st.serverUrl.isEmpty ? '服务器模式 · 未填写地址' : '服务器模式 · ${st.serverUrl}'),
                          style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openConnect,
                    ),
                    ListTile(
                      leading: const Icon(Icons.auto_awesome_outlined),
                      title: const Text('外观'),
                      subtitle: const Text('液态玻璃主题 · 跟随系统或手动指定', style: TextStyle(fontSize: 12)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: GlassTabs(
                        labels: const ['跟随系统', '浅色', '深色'],
                        index: switch (st.themeMode) {
                          ThemeMode.light => 1,
                          ThemeMode.dark => 2,
                          _ => 0,
                        },
                        onChanged: (i) => AppState.I.setThemeMode(switch (i) {
                          1 => ThemeMode.light,
                          2 => ThemeMode.dark,
                          _ => ThemeMode.system,
                        }),
                      ),
                    ),
                    if (!st.direct)
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
                    ListenableBuilder(
                      listenable: ClassReminderService.I,
                      builder: (_, __) => SwitchListTile(
                        secondary: const Icon(Icons.notifications_active_outlined),
                        title: const Text('上课提醒'),
                        subtitle: Text(
                            ClassReminderService.I.enabled
                                ? '课前 ${ClassReminderService.leadMinutes} 分钟通知（'
                                    '无需打开 App，重启后仍有效）'
                                : '课前 ${ClassReminderService.leadMinutes} 分钟通知，后台也能收到',
                            style: const TextStyle(fontSize: 12)),
                        value: ClassReminderService.I.enabled,
                        onChanged: _onReminderToggle,
                      ),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.visibility_off_outlined),
                      title: const Text('上完的课淡化显示'),
                      subtitle: const Text('关闭后已上完的课与普通课一样显示正常彩色（需已设学期起点）',
                          style: TextStyle(fontSize: 12)),
                      value: st.dimCompleted,
                      onChanged: (v) => AppState.I.setDimCompleted(v),
                    ),
                    ListTile(
                      leading: const Icon(Icons.feedback_outlined),
                      title: const Text('提交反馈'),
                      subtitle: const Text('Issue · PR · Fork · GitHub（GPL-3.0）',
                          style: TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const FeedbackPage())),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (loggedIn && !st.demo)
                AppCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(Icons.logout, color: SemColors.danger),
                    title: Text('退出登录',
                        style: TextStyle(
                            color: SemColors.danger, fontWeight: FontWeight.w600)),
                    onTap: _logout,
                  ),
                ),
              if (st.demo)
                AppCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(Icons.science_outlined, color: SemColors.accent),
                    title: Text('退出演示模式',
                        style: TextStyle(
                            color: SemColors.accent, fontWeight: FontWeight.w600)),
                    onTap: () async {
                      await AppState.I.setDemo(false);
                    },
                  ),
                ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                    st.direct
                        ? 'AntiSIT · 直连模式（本机访问学校系统，数据不经过服务器）'
                        : (st.serverUrl.isEmpty
                            ? 'AntiSIT · 服务器模式（地址未填写，见连接设置）'
                            : 'AntiSIT · 数据来自 ${st.serverUrl} 开放接口'),
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
              child: Text(k, style: TextStyle(fontSize: 13, color: SemColors.textMuted)),
            ),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}
