import 'package:campus_core/campus_core.dart';

/// AI 提供商插件：Gemini（Google，官方 OpenAI 兼容层）。
class GeminiProvider extends AiProviderPlugin {
  const GeminiProvider();

  static const pluginId = 'gemini';

  @override
  String get id => pluginId;
  @override
  String get label => 'Gemini';
  @override
  String get description => 'Google AI Studio';
  @override
  String get baseUrl => 'https://generativelanguage.googleapis.com/v1beta/openai';
  @override
  List<String> get models => const [
        'gemini-3.7-flash', 'gemini-3.5-flash-lite', 'gemini-3.1-pro-preview',
        'gemini-2.5-pro', 'gemini-2.5-flash',
      ];
  @override
  String get defaultModel => 'gemini-2.5-flash';
  @override
  String get docs => 'https://aistudio.google.com/app/apikey';
  @override
  String get applyLabel => '申请 API Key';
  @override
  String get logo => 'packages/plugin_ai_gemini/assets/gemini.svg';

  /// 兼容层用 `reasoning_effort`（off → none）。
  @override
  Map<String, dynamic> thinkingOff(String model) => const {'reasoning_effort': 'none'};
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_AI_GEMINI=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(providers: [GeminiProvider()]);
