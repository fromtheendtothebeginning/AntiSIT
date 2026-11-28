import 'package:campus_core/campus_core.dart';

/// AI 提供商插件：Kimi（月之暗面）。
class KimiProvider extends AiProviderPlugin {
  const KimiProvider();

  static const pluginId = 'kimi';

  @override
  String get id => pluginId;
  @override
  String get label => 'Kimi（月之暗面）';
  @override
  String get description => '月之暗面官方';
  @override
  String get baseUrl => 'https://api.moonshot.cn/v1';
  @override
  List<String> get models =>
      const ['kimi-k3', 'kimi-k2.7-code', 'kimi-k2.7-code-highspeed', 'kimi-k2.6', 'kimi-k2.5'];
  @override
  String get defaultModel => 'kimi-k3';
  @override
  String get docs => 'https://platform.moonshot.cn/console/api-keys';
  @override
  String get applyLabel => '申请 API Key';
  @override
  String get logo => 'packages/plugin_ai_kimi/assets/kimi.svg';

  /// k3 用 `reasoning_effort`，K2.x 用 `thinking: {type: disabled}`。
  @override
  Map<String, dynamic> thinkingOff(String model) => model.startsWith('kimi-k3')
      ? const {'reasoning_effort': 'none'}
      : const {
          'thinking': {'type': 'disabled'}
        };

  /// k3 认 reasoning_effort 分档；K2.x 只有 thinking.type 两态。
  @override
  Map<String, dynamic> reasoningEffort(String model, String effort) {
    if (model.startsWith('kimi-k3')) return {'reasoning_effort': effort};
    return effort == 'none'
        ? const {'thinking': {'type': 'disabled'}}
        : const {'thinking': {'type': 'enabled'}};
  }
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；--dart-define=EXCLUDE_AI_KIMI=true 时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(providers: [KimiProvider()]);
