import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

/// 「我的」页头部卡：登录后显示模式与学校，未登录 / 演示模式给登录入口。
Widget profileHeaderCard(
  BuildContext context, {
  required AppState st,
  required bool loggedIn,
  required VoidCallback? onTap,
}) {
  return AppCard(
    onTap: onTap,
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
  );
}

/// 未登录 / 演示模式下的登录入口卡。
Widget profileGuestCard({required AppState st, required VoidCallback onTap}) {
  return AppCard(
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
      onTap: onTap,
    ),
  );
}

/// 校园凭据未填写完整的提示条。
Widget profileCredentialsBanner({required bool direct}) {
  return Container(
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: SemColors.dangerSoft,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: SemColors.danger.withValues(alpha: 0.3)),
    ),
    child: Text(
      direct
          ? '校园凭据未填写完整：请在「连接设置 → 直连模式」填写学号与统一身份认证密码，才能查询校园数据。'
          : '校园凭据未配置：请登录所用服务器的网站 →「我的 → 校园服务」填写学号与 VPN 密码，隧道类查询才能使用。',
      style: TextStyle(fontSize: 12.5, color: SemColors.danger, height: 1.6),
    ),
  );
}

/// 未开启 AI 自动识别验证码的提示条。
Widget profileCaptchaBanner() {
  return Container(
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
  );
}

/// 学籍信息卡：可点标题收起。
Widget profileStudentCard({
  required Map<String, dynamic>? info,
  required bool open,
  required bool configured,
  required VoidCallback onToggle,
}) {
  return AppCard(
    onTap: onToggle,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        profileSectionHeader('学籍信息', open),
        profileCollapsible(
          open,
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
                profileKv('年级', '${info['nj'] ?? '-'}'),
                profileKv('学院', '${info['bmmc'] ?? '-'}'),
                profileKv('专业', '${info['zymc'] ?? '-'}'),
                profileKv('班级', '${info['bjmc'] ?? '-'}'),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// 服务状态卡：连通状态、各项就绪情况与断开入口。
Widget profileServiceCard({
  required AppState st,
  required Map<String, dynamic>? status,
  required bool connected,
  required bool loading,
  required bool open,
  required VoidCallback onToggle,
  required VoidCallback onDisconnect,
}) {
  return AppCard(
    onTap: onToggle,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('服务状态', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            if (loading)
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
            Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 20, color: SemColors.textMuted),
          ],
        ),
        profileCollapsible(
          open,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  profileReadyChip('学工登录', status?['cas_ready'] as bool?),
                  profileReadyChip('教务登录', status?['jwxt_ready'] as bool?),
                  profileReadyChip('支付密码', status?['has_pay_password'] as bool?),
                  profileReadyChip('默认寝室', status?['has_dorm'] as bool?),
                ],
              ),
              if (connected || st.direct)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onDisconnect,
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
  );
}

/// 退出登录卡。
Widget profileLogoutCard({required VoidCallback onLogout}) {
  return AppCard(
    padding: EdgeInsets.zero,
    child: ListTile(
      leading: Icon(Icons.logout, color: SemColors.danger),
      title: Text('退出登录',
          style: TextStyle(
              color: SemColors.danger, fontWeight: FontWeight.w600)),
      onTap: onLogout,
    ),
  );
}

/// 退出演示模式卡。
Widget profileDemoExitCard() {
  return AppCard(
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
  );
}

/// 页底说明、数据来源与版本 / 协议信息。
List<Widget> profileFooter({
  required AppState st,
  required String? version,
  required VoidCallback onLicense,
}) {
  return [
    const SizedBox(height: 14),
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
        onTap: onLicense,
        child: Text(
          [if (version != null) version, 'GPL-3.0 开源协议'].join(' · '),
          style: TextStyle(fontSize: 11, color: SemColors.textMuted, height: 1.5),
        ),
      ),
    ),
  ];
}

Widget profileSectionHeader(String title, bool open) => Row(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const Spacer(),
        Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 20, color: SemColors.textMuted),
      ],
    );

/// 可收起内容的高度过渡：顶部锚定的 AnimatedSize（默认居中会让内容在动画期间
/// 整体上下漂移），收起时留一个零高占位保持宽度。
Widget profileCollapsible(bool open, Widget content) => AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: open ? content : const SizedBox(width: double.infinity, height: 0),
    );

Widget profileReadyChip(String label, bool? ready) {
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

Widget profileKv(String k, String v) => Padding(
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
