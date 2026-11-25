import 'package:campus_core/campus_core.dart';

/// AI 提供商插件：OpenCode Go（opencode.ai 聚合订阅），一个 Key 调多家模型。
/// 部分模型在聚合侧内部走 Anthropic / responses 端点，此处仍只按 OpenAI 兼容协议调用。
class OpenCodeGoProvider extends AiProviderPlugin {
  const OpenCodeGoProvider();

  static const pluginId = 'opencode-go';

  @override
  String get id => pluginId;
  @override
  String get label => 'OpenCode Go';
  @override
  String get description => 'opencode.ai 聚合订阅（一个 Key 用多家模型）';
  @override
  String get baseUrl => 'https://opencode.ai/zen/go/v1';
  @override
  List<String> get models => const [
        'deepseek-v4-flash', 'deepseek-v4-pro', 'deepseek-v4-flash-vision-exp',
        'glm-5.3', 'glm-5.2', 'glm-5.1', 'kimi-k3', 'kimi-k2.7-code', 'kimi-k2.6',
        'mimo-v2.5', 'mimo-v2.5-pro', 'qwen3.8-max', 'qwen3.7-max', 'qwen3.7-plus',
        'qwen3.6-plus', 'grok-4.5', 'gpt-5.6-luna', 'minimax-m3', 'minimax-m2.7',
        'hy3', 'ox-alpha-free',
      ];
  @override
  String get defaultModel => 'deepseek-v4-flash';
  @override
  String get docs => 'https://opencode.ai/docs/go/';
  @override
  String get applyLabel => '订阅 / 查看用量';
  @override
  String get logo => 'packages/plugin_ai_opencode_go/assets/opencode-go.svg';

  /// 不关思考：各上游 thinking / reasoning_effort / enable_thinking 写法混杂，统一加易 400。
  @override
  Map<String, dynamic> thinkingOff(String model) => const {};
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；--dart-define=EXCLUDE_AI_OPENCODE_GO=true 时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(providers: [OpenCodeGoProvider()]);
