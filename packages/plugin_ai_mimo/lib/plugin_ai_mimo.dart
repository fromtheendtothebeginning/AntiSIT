import 'package:campus_core/campus_core.dart';

/// AI 提供商插件：MiMo（小米）按量付费。
class MimoProvider extends AiProviderPlugin {
  const MimoProvider();

  static const pluginId = 'mimo';

  @override
  String get id => pluginId;
  @override
  String get label => 'MiMo';
  @override
  String get description => '小米 MiMo 开放平台（按量付费）';
  @override
  String get baseUrl => 'https://api.xiaomimimo.com/v1';
  /// 只列支持识图的对话模型（asr / tts 用不上，v2.5 系列已下线）。
  @override
  List<String> get models =>
      const ['mimo-v2.6-flash', 'mimo-v2.6-pro', 'mimo-v2.6-pro-ultraspeed'];
  @override
  String get defaultModel => 'mimo-v2.6-flash';
  @override
  String get docs => 'https://platform.xiaomimimo.com/#/console/api-keys';
  @override
  String get applyLabel => '申请 API Key';
  @override
  String get logo => 'packages/plugin_ai_mimo/assets/mimo.svg';

  /// 用 `reasoning_effort: none` 关思考；官方文档的 `thinking` 字段实测会弄错结果。
  @override
  Map<String, dynamic> thinkingOff(String model) => const {'reasoning_effort': 'none'};
}

/// Token Plan 订阅套餐：独立域名（cn / sgp / ams），Key 与按量付费不可互换。
class MimoTokenPlanProvider extends AiProviderPlugin {
  const MimoTokenPlanProvider();

  static const pluginId = 'mimotokenplan';

  @override
  String get id => pluginId;
  @override
  String get label => 'MiMo Token Plan';
  @override
  String get description => '小米 MiMo 订阅套餐（独立域名与 Key）';
  @override
  String get baseUrl => 'https://token-plan-cn.xiaomimimo.com/v1';
  /// 套餐不含 `mimo-v2.6-pro-ultraspeed`，不列。
  @override
  List<String> get models => const ['mimo-v2.6-flash', 'mimo-v2.6-pro'];
  @override
  String get defaultModel => 'mimo-v2.6-flash';
  @override
  String get docs => 'https://platform.xiaomimimo.com/#/token-plan';
  @override
  String get applyLabel => '订阅 Token Plan';
  @override
  String get logo => 'packages/plugin_ai_mimo/assets/mimo.svg';

  @override
  Map<String, dynamic> thinkingOff(String model) => const {'reasoning_effort': 'none'};
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；--dart-define=EXCLUDE_AI_MIMO=true 时整包被摇掉。
const PluginBundle pluginBundle =
    PluginBundle(providers: [MimoProvider(), MimoTokenPlanProvider()]);
