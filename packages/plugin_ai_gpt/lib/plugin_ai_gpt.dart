import 'package:campus_core/campus_core.dart';

/// AI 提供商插件：GPT（OpenAI 官方）。
class GptProvider extends AiProviderPlugin {
  const GptProvider();

  static const pluginId = 'gpt';

  @override
  String get id => pluginId;
  @override
  String get label => 'GPT';
  @override
  String get description => 'OpenAI 官方';
  @override
  String get baseUrl => 'https://api.openai.com/v1';
  @override
  List<String> get models =>
      const ['gpt-5', 'gpt-5-mini', 'gpt-5-nano', 'gpt-4.1', 'gpt-4.1-mini', 'gpt-4o'];
  @override
  String get defaultModel => 'gpt-5-mini';
  @override
  String get docs => 'https://platform.openai.com/api-keys';
  @override
  String get applyLabel => '申请 API Key';
  @override
  String get logo => 'packages/plugin_ai_gpt/assets/gpt.svg';

  /// 官方用 `reasoning_effort`（off → none）。
  @override
  Map<String, dynamic> thinkingOff(String model) => const {'reasoning_effort': 'none'};
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_AI_GPT=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(providers: [GptProvider()]);
