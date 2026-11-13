import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'backup_page.dart';

/// 备份与恢复：把本机课表 / 设置 / 学校档案 / 插件偏好导出为 JSON，
/// 卸载重装或换机后导入恢复。账号密码、登录态、AI Key 不在备份里。
class BackupPlugin extends FeaturePlugin {
  const BackupPlugin();

  static const pluginId = 'backup';

  @override
  String get id => pluginId;
  @override
  String get name => '备份与恢复';
  @override
  String get description => '导出 / 导入课表、设置、学校档案与插件偏好（不含账号密码与 AI Key）';
  @override
  int get settingsOrder => 65;

  @override
  List<Widget> settingsTiles(BuildContext context, PluginRegistry registry) => [
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('备份与恢复'),
          subtitle: const Text(
            '重装 / 换机前导出课表与设置（不含账号密码、登录态、AI Key）',
            style: TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const BackupPage())),
        ),
      ];
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
const PluginBundle pluginBundle = PluginBundle(features: [BackupPlugin()]);
