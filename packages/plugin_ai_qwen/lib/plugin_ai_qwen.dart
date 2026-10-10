import 'package:campus_core/campus_core.dart';

/// AI 提供商插件：Qwen（通义千问 / 阿里云百炼，走兼容模式端点）。
class QwenProvider extends AiProviderPlugin {
  const QwenProvider();

  static const pluginId = 'qwen';

  @override
  String get id => pluginId;
  @override
  String get label => 'Qwen（通义千问）';
  @override
  String get description => '阿里云百炼（DashScope 兼容模式）';
  @override
  String get baseUrl => 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  @override
  List<String> get models => const [
        'qwen3.8-max', 'qwen3.7-max', 'qwen3.7-plus', 'qwen3.6-plus',
        'qwen-max', 'qwen-plus', 'qwen-turbo',
      ];
  @override
  String get defaultModel => 'qwen-max';
  @override
  String get docs => 'https://bailian.console.aliyun.com/?apiKey=1';
  @override
  String get applyLabel => '申请 API Key';
  @override
  String get logo => 'packages/plugin_ai_qwen/assets/qwen.svg';

  /// 官方兼容模式用 `enable_thinking`（与 index `apply_thinking` 一致）。
  @override
  Map<String, dynamic> thinkingOff(String model) => const {'enable_thinking': false};
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_AI_QWEN=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(providers: [QwenProvider()]);
