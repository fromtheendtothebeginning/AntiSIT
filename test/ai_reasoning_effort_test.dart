import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ai/plugin_ai.dart';
import 'package:plugin_ai_deepseek/plugin_ai_deepseek.dart';

/// 思考深度 / 换模型：写法随提供商走，不能给所有家都塞 reasoning_effort。
void main() {
  setUp(() {
    PluginRegistry.I = PluginRegistry(providers: const [DeepSeekProvider()]);
  });

  test('DeepSeek 用 thinking.budget_tokens 分档，不走 reasoning_effort', () {
    const p = DeepSeekProvider();
    expect(p.reasoningEffort('deepseek-v4-pro', 'low')['thinking'], {
      'type': 'enabled',
      'budget_tokens': 2048,
    });
    expect(p.reasoningEffort('deepseek-v4-pro', 'high')['thinking'], {
      'type': 'enabled',
      'budget_tokens': 16384,
    });
    // 默认档（medium / 认不出的值）落中间，别把预算给到极大值
    expect(
      (p.reasoningEffort('deepseek-v4-pro', 'medium')['thinking']
          as Map)['budget_tokens'],
      8192,
    );
  });

  test('认不出的档位也回落到中间一档，不抛异常', () {
    const p = DeepSeekProvider();
    expect(
      (p.reasoningEffort('deepseek-flash', 'ultra')['thinking']
          as Map)['budget_tokens'],
      8192,
    );
  });

  test('请求体只在有档位时才加字段，空串不传', () {
    final cfg = AiConfig(
      enabled: true,
      providerId: DeepSeekProvider.pluginId,
      model: 'deepseek-flash',
    );
    final none = buildMessagesPayload(
      cfg,
      const [AiChatMessage(role: 'user', content: 'hi')],
      const [],
      512,
      false,
    );
    expect(none.containsKey('thinking'), isFalse);

    final high = buildMessagesPayload(
      cfg,
      const [AiChatMessage(role: 'user', content: 'hi')],
      const [],
      512,
      false,
      reasoningEffort: 'high',
    );
    expect(high['thinking'], {'type': 'enabled', 'budget_tokens': 16384});
  });
}
