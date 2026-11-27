import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:campus_core/campus_core.dart';
import '../update_check.dart';
import 'profile_dialogs.dart';
import 'profile_sections.dart';
import 'profile_settings_section.dart';
import 'update_center_page.dart';

/// 「我的」页：账号与学籍、服务状态、插件管理入口与各项设置。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _statusLoading = false;

  /// 学籍信息 / 服务状态两张卡默认展开，点标题收起。
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
        setState(
          () => _version =
              'v${info.version}${info.buildNumber.isEmpty ? '' : ' (${info.buildNumber})'}',
        );
      }
    } catch (_) {
      // 取不到就不显示，不影响页面
    }
  }

  /// 打开 GPL-3.0 协议原文（失败则复制链接，与反馈页同一套兜底）。
  Future<void> _openLicense() async {
    const url =
        'https://github.com/fromtheendtothebeginning/AntiSIT/blob/main/LICENSE';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(const ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制协议链接'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 手动检查更新：进二级页（页里自己查一次，并分别列出稳定版与内测版）。
  void _checkUpdate() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const UpdateCenterPage()));
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
      ToolCache.score = ToolCache.scoreOf(r['data']);
      AppState.I.studentInfo = ToolCache.score?.student;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _disconnectVpn() async {
    final direct = AppState.I.direct;
    await ApiClient.I.disconnect();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          direct ? '已清除直连会话，下次查询会重新登录学校系统' : '已断开 VPN 隧道，下次查询会自动重连',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
    if (!await confirmLogout(context, direct: direct)) return;
    await ApiClient.I.disconnect();
    // manual: 主动退出要连「记住密码并自动重登」一起关掉，否则下次 401 会拿旧密码登回去。
    if (direct) {
      await AppState.I.clearDirectSession(manual: true);
    } else {
      await AppState.I.clearSession(keepCreds: false, manual: true);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已退出登录'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openConnect() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ConnectPage()));
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

        // 顶栏留白要在建 Scaffold 之前算（body 里的 MediaQuery 已被扣掉状态栏）
        final topInset = glassTopInset(context);
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(
            context,
            title: const Text('我的'),
            actions: [
              if (loggedIn)
                IconButton(
                  onPressed: _statusLoading ? null : _refreshAll,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新状态',
                ),
            ],
          ),
          body: GlassFadedBody(
            barHeight: topInset,
            child: ListView(
              // 底栏与顶栏都是玻璃浮层：列表上下要多让出这一截
              padding: EdgeInsets.fromLTRB(
                12,
                4 + topInset,
                12,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                profileHeaderCard(
                  context,
                  st: st,
                  loggedIn: loggedIn,
                  onTap: loggedIn || st.demo ? null : _goLogin,
                ),
                const SizedBox(height: 10),
                if (!loggedIn)
                  profileGuestCard(
                    st: st,
                    onTap: st.demo ? _exitDemoAndLogin : _goLogin,
                  ),
                if (!loggedIn) const SizedBox(height: 10),
                if (loggedIn) ...[
                  if (!configured && !st.demo)
                    profileCredentialsBanner(direct: st.direct),
                  if (configured &&
                      status?['auto_captcha'] != true &&
                      !st.direct)
                    profileCaptchaBanner(),
                  profileStudentCard(
                    info: info,
                    open: _infoOpen,
                    configured: configured,
                    onToggle: () => setState(() => _infoOpen = !_infoOpen),
                  ),
                  const SizedBox(height: 10),
                  profileServiceCard(
                    st: st,
                    status: status,
                    connected: connected,
                    loading: _statusLoading,
                    open: _statusOpen,
                    onToggle: () => setState(() => _statusOpen = !_statusOpen),
                    onDisconnect: _disconnectVpn,
                  ),
                  const SizedBox(height: 10),
                ],
                profileSettingsCard(
                  context,
                  st: st,
                  version: _version,
                  onOpenConnect: _openConnect,
                  onCheckUpdate: _checkUpdate,
                ),
                const SizedBox(height: 10),
                if (loggedIn && !st.demo) profileLogoutCard(onLogout: _logout),
                if (st.demo) profileDemoExitCard(),
                const SizedBox(height: 14),
                ...profileFooter(
                  st: st,
                  version: _version,
                  onLicense: _openLicense,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
