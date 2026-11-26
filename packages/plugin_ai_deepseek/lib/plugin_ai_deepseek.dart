import 'package:campus_core/campus_core.dart';

/// AI 提供商插件：DeepSeek（深度求索官方），走 OpenAI 兼容端点。
class DeepSeekProvider extends AiProviderPlugin {
  const DeepSeekProvider();

  static const pluginId = 'deepseek';

  @override
  String get id => pluginId;
  @override
  String get label => 'DeepSeek';
  @override
  String get description => '深度求索官方';
  @override
  String get baseUrl => 'https://api.deepseek.com';
  @override
  List<String> get models => const ['deepseek-flash', 'deepseek-v4-pro'];
  @override
  String get defaultModel => 'deepseek-flash';
  @override
  String get docs => 'https://platform.deepseek.com/api_keys';
  @override
  String get applyLabel => '申请 API Key';
  @override
  String get logo => 'packages/plugin_ai_deepseek/assets/deepseek.svg';

  /// 关思考固定发 `thinking: {type: disabled}`，与官方 index 一致。
  @override
  Map<String, dynamic> thinkingOff(String model) => const {
        'thinking': {'type': 'disabled'}
      };
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；--dart-define=EXCLUDE_AI_DEEPSEEK=true 时整包被摇掉。
const PluginBundle pluginBundle = PluginBundle(providers: [DeepSeekProvider()]);
