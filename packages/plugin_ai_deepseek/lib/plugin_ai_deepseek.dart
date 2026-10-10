import 'package:campus_core/campus_core.dart';

/// AI 提供商插件：DeepSeek（深度求索官方）。
/// OpenAI 兼容端点；`GET {base}/models` 拿真实可用列表，下面的内置列表只在拉取失败时兜底。
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
  /// deepseek-v4-flash-vision-exp 将下架，已从内置列表移除。
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

  /// 官方文档：`thinking{"type":"disabled"}` 关思考（与 index `apply_thinking(level="off")` 一致）。
  @override
  Map<String, dynamic> thinkingOff(String model) => const {
        'thinking': {'type': 'disabled'}
      };
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_AI_DEEPSEEK=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(providers: [DeepSeekProvider()]);
