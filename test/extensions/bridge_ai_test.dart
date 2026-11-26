import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpExtensionEnv();

  group('接口：ai.chat（提示词本地转义成提供商请求）', () {
    late FakeAiCapability ai;

    setUp(() {
      ai = FakeAiCapability();
      PluginRegistry.I = PluginRegistry(
        features: [WebViewPlugin(), ExtPlugin(), FakeAiPlugin(ai)],
        themes: const [GlassTheme()],
        capabilities: {
          PluginIds.webview: WebViewCapabilityImpl(),
          PluginIds.ai: ai,
        },
      );
    });

    Future<ExtBridge> bridge(WidgetTester tester, {ExtensionItem? item}) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      return ExtBridge(
        extId: 'e1',
        context: tester.element(find.byType(SizedBox)),
        item: item,
      );
    }

    testWidgets('用户自己加的拓展直接能用：提示词与参数进能力，回答文本出来', (tester) async {
      final b = await bridge(tester);
      expect(
        await b.call('ai.chat', {'prompt': ' 你好 ', 'system': '你是助手'}),
        '好的',
      );
      expect(ai.lastPrompt, '你好', reason: '两端空白去掉');
      expect(ai.lastSystem, '你是助手');
      expect(ai.lastMaxTokens, 1024, reason: '缺省 1024');
    });

    testWidgets('maxTokens 收在 16–4096；缺省 1024，不合法的值直接报错', (tester) async {
      final b = await bridge(tester);
      await b.call('ai.chat', {'prompt': 'x', 'maxTokens': 99999});
      expect(ai.lastMaxTokens, 4096);
      expect(await b.call('ai.chat', {'prompt': 'x'}), '好的');
      expect(ai.lastMaxTokens, 1024);
      await expectLater(
        b.call('ai.chat', {'prompt': 'x', 'maxTokens': 0}),
        throwsArgumentError,
        reason: '参数不对要报错，不静默回退',
      );
      await expectLater(
        b.call('ai.chat', {'prompt': 'x', 'maxTokens': '不是数字'}),
        throwsArgumentError,
      );
    });

    testWidgets('prompt / system 超长直接报错（不序列化超大请求体）', (tester) async {
      final b = await bridge(tester);
      await expectLater(
        b.call('ai.chat', {'prompt': 'x' * 40000}),
        throwsArgumentError,
      );
      await expectLater(
        b.call('ai.chat', {'prompt': 'x', 'system': 's' * 40000}),
        throwsArgumentError,
      );
      expect(ai.calls, 0, reason: '没到 AI 那一步就该拦下');
    });

    testWidgets('参数不对直接报错（Promise reject，不静默失败）', (tester) async {
      final b = await bridge(tester);
      await expectLater(b.call('ai.chat', null), throwsArgumentError);
      await expectLater(
        b.call('ai.chat', {'prompt': '   '}),
        throwsArgumentError,
        reason: 'prompt 不能是空的',
      );
      expect(ai.calls, 0);
    });

    testWidgets('市场装的拓展必须声明 ai 权限', (tester) async {
      final denied = await bridge(
        tester,
        item: marketExtItem(permissions: const ['storage']),
      );
      await expectLater(
        denied.call('ai.chat', {'prompt': 'x'}),
        throwsArgumentError,
      );
      expect(ai.calls, 0);

      final allowed = await bridge(
        tester,
        item: marketExtItem(permissions: const ['ai']),
      );
      expect(await allowed.call('ai.chat', {'prompt': 'x'}), '好的');
    });

    testWidgets('AI 不可用（停用 / 没配置）报「AI 还没配好」', (tester) async {
      ai.available = false;
      final b = await bridge(tester);
      await expectLater(
        b.call('ai.chat', {'prompt': 'x'}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('AI 还没配好'),
          ),
        ),
      );
    });

    testWidgets('AI 插件没装：同样报错，不崩', (tester) async {
      PluginRegistry.I = PluginRegistry(
        features: const [WebViewPlugin(), ExtPlugin()],
        themes: const [GlassTheme()],
        capabilities: const {PluginIds.webview: WebViewCapabilityImpl()},
      );
      final b = await bridge(tester);
      await expectLater(
        b.call('ai.chat', {'prompt': 'x'}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('AI 还没配好'),
          ),
        ),
      );
    });

    testWidgets('ai.chatTools：多轮消息 / 工具 schema 进能力，工具调用原样回网页', (tester) async {
      ai.chatToolsReply = const AiChatReply(
        text: '我看看',
        finishReason: 'tool_calls',
        usedTools: true,
        toolCalls: [
          AiToolCall(
            id: 'c1',
            name: 'read_file',
            argumentsJson: '{"path":"main.js"}',
          ),
        ],
      );
      final b = await bridge(tester);
      final out =
          await b.call('ai.chatTools', {
                'messages': [
                  {'role': 'system', 'content': '你是助手'},
                  {'role': 'user', 'content': '读 main.js'},
                  {
                    'role': 'assistant',
                    'content': '',
                    'toolCalls': [
                      {'id': 'c0', 'name': 'list_files', 'arguments': '{}'},
                    ],
                  },
                  {
                    'role': 'tool',
                    'content': 'main.js 90 B',
                    'toolCallId': 'c0',
                  },
                ],
                'tools': [
                  {
                    'type': 'function',
                    'function': {
                      'name': 'read_file',
                      'description': '读文件',
                      'parameters': {
                        'type': 'object',
                        'properties': {
                          'path': {'type': 'string'},
                        },
                      },
                    },
                  },
                ],
                'maxTokens': 99999,
              })
              as Map;

      expect(ai.chatToolsCalls, 1);
      expect(ai.lastChatToolsMaxTokens, 4096);
      expect(ai.lastMessages, hasLength(4));
      expect(ai.lastMessages![0].role, 'system');
      expect(ai.lastMessages![2].toolCalls.single.name, 'list_files');
      expect(ai.lastMessages![3].toolCallId, 'c0', reason: '工具结果要带回对应的调用 id');
      expect(ai.lastTools!.single.name, 'read_file');
      expect(ai.lastTools!.single.description, '读文件');
      expect(out['text'], '我看看');
      expect(out['usedTools'], isTrue);
      expect(out['finishReason'], 'tool_calls');
      expect((out['toolCalls'] as List).single, {
        'id': 'c1',
        'name': 'read_file',
        'arguments': '{"path":"main.js"}',
      });
    });

    testWidgets('ai.chatToolsStream：增量事件推给网页，最终带 reasoning', (tester) async {
      ai.chatToolsReply = const AiChatReply(
        text: '流式回答',
        reasoning: '先想一下',
        usedTools: true,
      );
      final b = await bridge(tester);
      final sink = RecordingSink();
      b.attachEventSink(sink);

      final out =
          await b.call('ai.chatToolsStream', {
                'streamId': 's1',
                'messages': [
                  {'role': 'user', 'content': '写个拓展'},
                ],
              })
              as Map;

      expect(ai.chatToolsStreamCalls, 1);
      expect(out['text'], '流式回答');
      expect(out['reasoning'], '先想一下');
      expect(sink.events.map((e) => e.$1).toSet(), {'ai.stream'});
      final kinds = [for (final e in sink.events) (e.$2 as Map)['kind']];
      expect(kinds, ['reasoning', 'text']);
      expect((sink.events.first.$2 as Map)['streamId'], 's1');
    });

    testWidgets('ai.chatTools：空 messages 报错；市场拓展同样要声明 ai 权限', (tester) async {
      final b = await bridge(tester);
      await expectLater(
        b.call('ai.chatTools', {'messages': []}),
        throwsArgumentError,
      );
      await expectLater(b.call('ai.chatTools', null), throwsArgumentError);
      expect(ai.chatToolsCalls, 0);

      final denied = await bridge(
        tester,
        item: marketExtItem(permissions: const ['storage']),
      );
      await expectLater(
        denied.call('ai.chatTools', {
          'messages': [
            {'role': 'user', 'content': 'x'},
          ],
        }),
        throwsArgumentError,
      );
      expect(ai.chatToolsCalls, 0);
    });

    test('ai 是敏感权限：安装弹窗的说明列表会带上它', () {
      final out = describeSensitivePermissions(['ai', 'storage']);
      expect(out, contains('调用 AI 对话（用你配置的模型与 API Key，可能产生费用）'));
      expect(out, hasLength(2));
    });
  });
}

