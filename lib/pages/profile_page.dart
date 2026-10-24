import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:campus_core/campus_core.dart';
import '../update_check.dart';
import '../widgets/update_dialog.dart';
import 'plugin_manager_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _statusLoading = false;

  /// 学籍信息 / 服务状态默认展开，点标题收起（两张卡都挺长，想只看头部提要时收掉）。
  bool _infoOpen = true;
  bool _statusOpen = true;

  @override
  void initState() {
    super.initState();
    _refreshAll();
    _loadVersion();
    UpdateChecker.I.load(); // 本机版本 + 上次点过「稍后」的版本
  }

  /// 运行时版本号（读 APK 里的 versionName/versionCode，不用手写常量）。
  String? _version;
  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version =
            'v${info.version}${info.buildNumber.isEmpty ? '' : ' (${info.buildNumber})'}');
      }
    } catch (_) {
      // 取不到就不显示，不影响页面
    }
  }

  /// 打开 GPL-3.0 协议原文（失败则复制链接，与反馈页同一套兜底）。
  Future<void> _openLicense() async {
    const url = 'https://github.com/fromtheendtothebeginning/AntiSIT/blob/main/LICENSE';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(const ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制协议链接'), behavior: SnackBarBehavior.floating));
    }
  }

  /// 手动检查更新：有新版就弹引导，否则给一句结果（已是最新 / 失败原因）。
  Future<void> _checkUpdate() async {
    await UpdateChecker.I.load();
    await UpdateChecker.I.check();
    if (!mounted) return;
    final uc = UpdateChecker.I;
    final info = uc.available;
    if (info != null) {
      await showUpdateDialog(context, info);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(uc.error != null ? '检查更新失败：${uc.error}' : '已是最新版本'),
        behavior: SnackBarBehavior.floating));
  }

  /// 「设置」卡里的「检查更新」条目：平时显示当前版本，查到新版本就地标出来。
  Widget _updateTile() => ListenableBuilder(
        listenable: UpdateChecker.I,
        builder: (context, _) {
          final uc = UpdateChecker.I;
          final info = uc.available;
          return ListTile(
            leading: const Icon(Icons.system_update_alt_outlined),
            title: const Text('检查更新'),
            subtitle: Text(
              info != null
                  ? '发现新版本 v${info.version}'
                  : (uc.error != null
                      ? '检查失败：${uc.error}'
                      : (_version == null ? '看看 GitHub 上有没有新版本' : '当前 $_version')),
              style: TextStyle(
                  fontSize: 12, color: info != null ? SemColors.accent : null),
            ),
            trailing: uc.checking
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: uc.checking ? null : _checkUpdate,
          );
        },
      );

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
      ToolCache.score = ToolCache.scoreOf(r['data']);
      AppState.I.studentInfo = ToolCache.score?.student;
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

  @override
  Widget build(BuildContext context) {
    final st = AppState.I;
    return ListenableBuilder(
      // 注册表也要听：插件增删的设置条目 / 主题名 / 启用计数都来自它
      listenable: Listenable.merge([st, PluginRegistry.I]),
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
                            child: st.direct
                                ? Text(
                                    st.school.name.characters.first.toUpperCase(),
                                    style: TextStyle(
                                        fontSize: 22, fontWeight: FontWeight.bold,
                                        color: SemColors.accent),
                                  )
                                // 用户名 / 学号不外显（截图隐私）：服务器模式放通用人像
                                : Icon(Icons.person_outline, size: 30, color: SemColors.accent),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                                st.direct ? '直连模式 · ${st.school.name}' : '服务器模式',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold,
                                    color: SemColors.textPrimary)),
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

                // 学籍信息
                AppCard(
                  onTap: () => setState(() => _infoOpen = !_infoOpen),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader('学籍信息', _infoOpen),
                      _collapsible(
                        _infoOpen,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // 服务状态
                AppCard(
                  onTap: () => setState(() => _statusOpen = !_statusOpen),
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
                          const SizedBox(width: 4),
                          Icon(_statusOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                              size: 20, color: SemColors.textMuted),
                        ],
                      ),
                      _collapsible(
                        _statusOpen,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                    if (!st.direct)
                      ListenableBuilder(
                        listenable: AppState.I,
                        builder: (_, __) => SwitchListTile(
                          secondary: const Icon(Icons.lock_outline),
                          title: const Text('记住密码并自动重登'),
                          value: st.remember,
                          onChanged: (v) => AppState.I.setRemember(v),
                        ),
                      ),
                    // 由各插件贡献（课程表设置 / AI 设置 / 外观 / 提交反馈）：
                    // 插件停用或从清单里删掉，这里的条目自动消失。
                    // 课表相关的那几项（学期 / 调休 / 上课提醒 / 淡化）收在自己的二级页里，
                    // 这里只留一行「课程表设置」入口，见 plugin_timetable。
                    ...PluginRegistry.I.settingsTiles(context),
                    ListTile(
                      leading: const Icon(Icons.extension_outlined),
                      title: const Text('插件管理'),
                      subtitle: Text(
                          '${PluginRegistry.I.enabled.length} 个功能插件启用中 · 查看依赖关系',
                          style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const PluginManagerPage())),
                    ),
                    _updateTile(),
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
              // 从组件边上挪下来的说明，统一沉到页底
              if (st.direct)
                PageNotes(lines: [
                  '直连模式：数据由本机直接访问学校系统，不走任何服务器，'
                      '需在校园网 / 校内 VPN 内；登录验证码由 AI 自动识别'
                      '（可在「AI 设置」里配置），未配置则弹框手动输入。',
                ]),
              const SizedBox(height: 6),
              Center(
                child: Text(
                    st.direct
                        ? 'AntiSIT · 直连模式（本机访问学校系统，数据不经过服务器）'
                        : (st.serverUrl.isEmpty
                            ? 'AntiSIT · 服务器模式（地址未填写，见连接设置）'
                            : 'AntiSIT · 数据来自 ${st.serverUrl} 开放接口'),
                    style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
              ),
              const SizedBox(height: 6),
              Center(
                child: GestureDetector(
                  onTap: _openLicense,
                  child: Text(
                    [if (_version != null) _version!, 'GPL-3.0 开源协议'].join(' · '),
                    style: TextStyle(fontSize: 11, color: SemColors.textMuted, height: 1.5),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 可收起卡片的标题行：右边的箭头表示「点一下收起 / 展开」（整张卡都是热区）。
  Widget _sectionHeader(String title, bool open) => Row(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 20, color: SemColors.textMuted),
        ],
      );

  /// 可收起内容的高度过渡：顶部锚定的 AnimatedSize（默认居中会让内容在动画期间
  /// 整体上下漂移），收起时留一个零高占位保持宽度。
  Widget _collapsible(bool open, Widget content) => AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: open ? content : const SizedBox(width: double.infinity, height: 0),
      );

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
