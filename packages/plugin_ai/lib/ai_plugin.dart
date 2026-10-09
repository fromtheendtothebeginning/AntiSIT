import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';
import 'ai_settings_page.dart';

/// AI 设置：直连模式下自动识别验证码、识别校历截图里的调休。
/// 停用它 → [AiVision.available] 变 false → 验证码退回人工输入、校历识别入口消失，
/// 但课表本身照常用（所以它只是课程表的软依赖）。
class AiPlugin extends FeaturePlugin {
  const AiPlugin();

  static const pluginId = 'ai';

  @override
  String get id => pluginId;
  @override
  String get name => 'AI 设置';
  @override
  String get description => '配置 AI 提供商与模型，用于自动识别验证码、识别校历调休';
  @override
  List<String> get dependencies => const [PluginIds.network];
  @override
  int get settingsOrder => 60;

  @override
  Future<void> init() async {
    // 启动就读一次配置，「我的 → 设置」里的摘要才准
    await AiVision.I.load();
  }

  @override
  List<Widget> settingsTiles(BuildContext context, PluginRegistry registry) =>
      const [_AiSettingsTile()];
}

/// 状态摘要要在从设置页返回后刷新，所以自带一个 StatefulWidget。
class _AiSettingsTile extends StatefulWidget {
  const _AiSettingsTile();

  @override
  State<_AiSettingsTile> createState() => _AiSettingsTileState();
}

class _AiSettingsTileState extends State<_AiSettingsTile> {
  @override
  Widget build(BuildContext context) {
    final vision = AiVision.I;
    return ListTile(
      leading: const Icon(Icons.auto_awesome_outlined),
      title: const Text('AI 设置'),
      subtitle: Text(
        vision.available ? '已启用 · ${vision.config.summary}' : '未配置：自动识别验证码、识别校历调休',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const AiSettingsPage()));
        if (mounted) setState(() {});
      },
    );
  }
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_XXX=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(features: [AiPlugin()]);
