import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';
import 'ai_capability_impl.dart';
import 'ai_settings_page.dart';
import 'ai_vision.dart';

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

/// 内置的「自定义」提供商：任意 OpenAI 兼容服务，地址由用户自己填。
/// 它是兜底入口（没有第二个包可删），所以留在公共 AI 插件里，不单独成包。
class CustomProvider extends AiProviderPlugin {
  const CustomProvider();

  @override
  String get id => 'custom';
  @override
  String get label => '自定义';
  @override
  String get description => '任意 OpenAI 兼容服务（地址自己填）';
  @override
  String get baseUrl => '';
  @override
  List<String> get models => const [];
  @override
  String get defaultModel => '';
  @override
  String get docs => '';
  @override
  String get applyLabel => '申请 API Key';
  @override
  String get logo => 'packages/plugin_ai/assets/custom.svg';

  /// 地址与模型都由用户填，协议不确定，不加任何思考字段。
  @override
  Map<String, dynamic> thinkingOff(String model) => const {};
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// `capabilities` 里的 key 就是本插件 id：别的插件（课表页）与 core（验证码弹窗）
/// 按「接口 + 这个 id」取用 AI 能力，谁都不 import 本包；本插件被停用时查不到，
/// 它们自然降级（验证码退回手输、校历识别入口消失）。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_AI=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉——各提供商是独立包，各有自己的
/// `EXCLUDE_AI_XXX` 开关（见 tool/gen_plugins.dart 打印出来的清单）。
const PluginBundle pluginBundle = PluginBundle(
  features: [AiPlugin()],
  providers: [CustomProvider()],
  capabilities: {PluginIds.ai: AiCapabilityImpl()},
);
