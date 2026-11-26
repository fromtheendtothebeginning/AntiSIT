import 'package:campus_core/campus_core.dart';

/// AI 提供商插件：MiniMax（国内站 api.minimax.cn，OpenAI 兼容端点）。
/// 模型 id 首字母大写；只有 M3 系列支持识图，M2.x 纯文本，故内置列表只列 M3。
class MiniMaxProvider extends AiProviderPlugin {
  const MiniMaxProvider();

  static const pluginId = 'minimax';

  @override
  String get id => pluginId;
  @override
  String get label => 'MiniMax';
  @override
  String get description => 'MiniMax 开放平台（按量付费）';
  @override
  String get baseUrl => 'https://api.minimax.cn/v1';
  @override
  List<String> get models => const ['MiniMax-M3'];
  @override
  String get defaultModel => 'MiniMax-M3';
  @override
  String get docs => 'https://platform.minimax.cn/user-center/basic-information/interface-key';
  @override
  String get applyLabel => '申请 API Key';
  @override
  String get logo => 'packages/plugin_ai_minimax/assets/minimax.svg';

  @override
  Map<String, dynamic> thinkingOff(String model) =>
      MiniMaxThinking.off(model);
}

/// M Plan（原 Token Plan）订阅：与按量付费同域名，靠 `sk-cp-` 前缀 Key 区分，两边不可互换。
/// 订阅 Key 只能调套餐内模型，要用 M3 得换按量付费 Key，所以这里只列套餐模型。
class MiniMaxTokenPlanProvider extends AiProviderPlugin {
  const MiniMaxTokenPlanProvider();

  static const pluginId = 'minimaxtokenplan';

  @override
  String get id => pluginId;
  @override
  String get label => 'MiniMax Token Plan';
  @override
  String get description => 'MiniMax 订阅（M Plan，只能调套餐内模型）';
  @override
  String get baseUrl => 'https://api.minimax.cn/v1';
  @override
  List<String> get models => const ['MiniMax-M3.1-Flash-Preview'];
  @override
  String get defaultModel => 'MiniMax-M3.1-Flash-Preview';
  @override
  String get docs => 'https://platform.minimax.cn/console/plan';
  @override
  String get applyLabel => '订阅 M Plan';
  @override
  String get logo => 'packages/plugin_ai_minimax/assets/minimax.svg';

  @override
  Map<String, dynamic> thinkingOff(String model) =>
      MiniMaxThinking.off(model);
}

/// 两家共用的关思考写法：M3 用 `thinking: {type: disabled}`（M2.x 忽略）；
/// M3.1 只支持 adaptive 思考，发 disabled 直接 400，改用最浅档 `reasoning_effort: low`。
abstract final class MiniMaxThinking {
  static Map<String, dynamic> off(String model) => model.startsWith('MiniMax-M3.1')
      ? const {'reasoning_effort': 'low'}
      : const {
          'thinking': {'type': 'disabled'}
        };
}

/// 插件包入口：tool/gen_plugins.dart 按包名登记；--dart-define=EXCLUDE_AI_MINIMAX=true 时整包被摇掉。
const PluginBundle pluginBundle =
    PluginBundle(providers: [MiniMaxProvider(), MiniMaxTokenPlanProvider()]);
