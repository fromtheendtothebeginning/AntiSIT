import 'package:campus_core/campus_core.dart';

/// AI 提供商插件：MiniMax（国内平台，OpenAI 兼容端点）。
///
/// 官方文档：https://platform.minimax.cn/docs （国际站是 api.minimax.io，这里用国内站）
/// model id 是首字母大写的 `MiniMax-M3` 这种形式；识图只有 M3 系列支持，M2.x 是纯文本，
/// 而本 App 的两个功能都要图片输入，所以只列 M3。
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

/// M Plan（原 Token Plan）订阅：与按量付费**同一个域名**，靠 Key 区分
/// （订阅 Key 是 `sk-cp-` 前缀，官方明确两边不可互换）。订阅 Key 只能调套餐内的
/// `MiniMax-M3.1-Flash-Preview`；要用 M3 得换按量付费的 Key，所以这里只列套餐模型。
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

/// 两家共用的关思考写法（官方文档 `text-openai-api`）：
/// `thinking{"type":"disabled"}` 在 M3 上生效、M2.x 被忽略；
/// 而 `MiniMax-M3.1-Flash-Preview` 只支持 adaptive 思考，发 disabled 直接 400，
/// 所以那种模型改用最浅的 `reasoning_effort`（官方档位只有 low/medium/high/xhigh/max）。
abstract final class MiniMaxThinking {
  static Map<String, dynamic> off(String model) => model.startsWith('MiniMax-M3.1')
      ? const {'reasoning_effort': 'low'}
      : const {
          'thinking': {'type': 'disabled'}
        };
}

/// 插件包入口：清单生成器（tool/gen_plugins.dart）按包名登记这个常量。
/// 编译期常量开关为真时（--dart-define=EXCLUDE_AI_MINIMAX=true），这一条连同包内代码
/// 一起变成不可达代码，被 AOT 摇树丢掉。
const PluginBundle pluginBundle =
    PluginBundle(providers: [MiniMaxProvider(), MiniMaxTokenPlanProvider()]);
