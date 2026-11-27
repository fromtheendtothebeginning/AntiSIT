import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';
import '../update_check.dart';

import 'config_page.dart';
import 'plugin_manager_page.dart';

/// 设置卡：连接设置、记住密码、配置、插件条目、插件管理与检查更新。
Widget profileSettingsCard(
  BuildContext context, {
  required AppState st,
  required String? version,
  required VoidCallback onOpenConnect,
  required VoidCallback onCheckUpdate,
}) {
  return AppCard(
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
          onTap: onOpenConnect,
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
        // 刷新行为与长期偏好（二课达标线等）收在「配置」二级页里。
        ListTile(
          leading: const Icon(Icons.tune_rounded),
          title: const Text('配置'),
          subtitle: const Text('工具页自动刷新 · 校园码刷新间隔 · 二课达标线',
              style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConfigPage())),
        ),
        // 由各插件贡献（课程表设置 / AI 设置 / 外观 / 提交反馈），插件停用则条目消失；
        // 课表相关项收在自己的二级页里，这里只留「课程表设置」入口。
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
        profileUpdateTile(version: version, onCheckUpdate: onCheckUpdate),
      ],
    ),
  );
}

/// 「检查更新」条目：平时显示当前版本，查到新版本就地标出来。
Widget profileUpdateTile({required String? version, required VoidCallback onCheckUpdate}) => ListenableBuilder(
      listenable: UpdateChecker.I,
      builder: (context, _) {
        final uc = UpdateChecker.I;
        final info = uc.available;
        return ListTile(
          leading: const Icon(Icons.system_update_alt_outlined),
          title: const Text('检查更新'),
          subtitle: Text(
            info != null
                ? '发现新版本 v${info.version}（${channelLabel(uc.channel)}）'
                : (uc.error != null
                    ? '检查失败：${uc.error}'
                    : (version == null
                        ? '${channelLabel(uc.channel)} · 看看有没有新版本'
                        : '$version · ${channelLabel(uc.channel)}')),
            style: TextStyle(
                fontSize: 12, color: info != null ? SemColors.accent : null),
          ),
          trailing: uc.checking
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.chevron_right),
          onTap: uc.checking ? null : onCheckUpdate,
        );
      },
    );
