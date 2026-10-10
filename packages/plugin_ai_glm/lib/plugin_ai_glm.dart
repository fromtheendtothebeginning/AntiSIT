import 'package:campus_core/campus_core.dart';

/// AI 提供商插件：GLM（智谱 AI）。
class GlmProvider extends AiProviderPlugin {
  const GlmProvider();

  static const pluginId = 'glm';

  @override
  String get id => pluginId;
  @override
  String get label => 'GLM（智谱 AI）';
  @override
  String get description => '智谱 AI 开放平台';
  @override
  String get baseUrl => 'https://open.bigmodel.cn/api/paas/v4';
  @override
  List<String> get models => const [
        'glm-5.3', 'glm-5.2', 'glm-5.1', 'glm-4.7', 'glm-4.7-flash', 'glm-4.6', 'glm-4.5-air',
      ];
  @override
  String get defaultModel => 'glm-4.6';
  @override
  String get docs => 'https://open.bigmodel.cn/usercenter/apikeys';
  @override
  String get applyLabel => '申请 API Key';
  @override
  String get logo => 'packages/plugin_ai_glm/assets/glm.svg';

  /// 不关思考：index 里 glm 的思考字段格式不确定，加了怕 400，交给模型默认。
  @override
  Map<String, dynamic> thinkingOff(String model) => const {};
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_AI_GLM=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle = PluginBundle(providers: [GlmProvider()]);
