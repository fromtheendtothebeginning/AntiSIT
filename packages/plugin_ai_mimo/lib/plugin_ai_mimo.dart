import 'package:campus_core/campus_core.dart';

/// AI 提供商插件：MiMo（小米）。同一个包贡献两条：按量付费与 Token Plan 订阅套餐
/// —— 两个产品的模型名一样、但域名与 Key 都不同（tp- / ttp- 前缀，官方明确不可互换），
/// 所以注册成两条，各自的 Key 分开存。
///
/// 官方文档：https://mimo.mi.com/docs （开放平台控制台 https://platform.xiaomimimo.com/）
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
  /// 只列能识图的对话模型（两个功能都吃图片输入；asr / tts 没用）。
  /// v2.5 系列 2026-10-21 下线，所以默认换成 v2.6-flash。
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

  /// 关思考用 `reasoning_effort`，**不用**官方文档写的 `thinking{"type":"disabled"}`：
  /// index 2026-09-10 在 api.xiaomimimo.com 实测 none/high 都生效（none 时
  /// reasoning_tokens=0），而 thinking 字段虽然被接受却会把结果弄错。
  @override
  Map<String, dynamic> thinkingOff(String model) => const {'reasoning_effort': 'none'};
}

/// Token Plan 订阅套餐：独立域名（国内 cn / 新加坡 sgp / 欧洲 ams），Key 与按量付费
/// 不可互换；`mimo-v2.6-pro-ultraspeed` 不在套餐内，所以不列。
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

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_AI_MIMO=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle =
    PluginBundle(providers: [MimoProvider(), MimoTokenPlanProvider()]);
