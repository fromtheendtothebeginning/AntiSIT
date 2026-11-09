import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_core/campus_core.dart';
import 'package:campus_service/plugins/bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_ai/plugin_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 识图请求的回归用例（issue #1：deepseek-flash 识别校历报「AI 返回空结果」）。
///
/// 根因：思考型模型默认就开着思考（官网：deepseek-flash「thinking 默认开启，默认档位 high」），
/// 推理内容与正式回答共享 max_tokens——思考把预算吃光后 content 为空、finish_reason=length，
/// 而老代码把它报成「模型可能不支持识图」，用户看到的是模型不行，实际是 token 被思考占了。
/// 现在：① 校历解析这类纯提取任务直接关思考；② 其余调用首次空回答自动关思考重试一次；
/// ③ 真的撞上 length 就如实说「被截断」，不再误判成不支持识图。
/// 真实调用要联网 + Key，这里用 MockClient 只验请求体与重试/报错行为。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PluginRegistry.I = buildAppRegistry();
    AiVision.clientOverride = null;
  });
  tearDown(() => AiVision.clientOverride = null);

  Future<void> configured() => AiVision.I.save(
      AiConfig(enabled: true, providerId: 'deepseek', model: 'deepseek-flash')
        ..setApiKey('sk-test'));

  /// 按顺序回放响应，返回记录下来的请求体。
  List<Map<String, dynamic>> stub(List<Map<String, dynamic>> replies) {
    final bodies = <Map<String, dynamic>>[];
    AiVision.clientOverride = MockClient((req) async {
      bodies.add(jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>);
      final r = replies[bodies.length - 1];
      return http.Response.bytes(utf8.encode(jsonEncode(r)), 200);
    });
    return bodies;
  }

  /// 一次对话响应：思考型模型会另外带回 reasoning_content，正式回答在 content。
  Map<String, dynamic> reply(String content, String finishReason) => {
        'choices': [
          {
            'message': {'content': content, 'reasoning_content': '（推理）'},
            'finish_reason': finishReason,
          }
        ],
      };

  test('首次空回答：自动关掉思考重试一次，第二次拿到结果', () async {
    await configured();
    final bodies = stub([reply('', 'length'), reply('成功', 'stop')]);

    final out = await AiVision.I.describeImage(Uint8List(4), prompt: '请只回复两个字：成功');

    expect(out, '成功');
    expect(bodies.length, 2, reason: '空回答要重试，但只重试一次');
    expect(bodies.first.containsKey('thinking'), isFalse, reason: '首次按模型默认（思考开启）发');
    expect(bodies.last['thinking'], {'type': 'disabled'}, reason: '重试必须显式关思考');
  });

  test('两次都空且被截断：报「截断」，不再说「不支持识图」', () async {
    await configured();
    stub([reply('', 'length'), reply('', 'length')]);

    await expectLater(
      AiVision.I.describeImage(Uint8List(4), prompt: 'x'),
      throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('截断'))),
    );
  });

  test('本来就没开思考的调用（验证码）不重试：只发一次', () async {
    await configured();
    final bodies = stub([reply('', 'stop')]);

    await expectLater(
      AiVision.I.describeImage(Uint8List(4), prompt: 'x', thinkingOff: true),
      throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('未返回内容'))),
    );
    expect(bodies.length, 1);
    expect(bodies.single['thinking'], {'type': 'disabled'});
  });

  test('识别校历：请求自带关思考字段，一次到位', () async {
    await configured();
    final bodies = stub([reply('[{"date": "2026-10-01", "type": "off"}]', 'stop')]);

    final rules = await parseHolidayImage(Uint8List(4), startDate: '2026-09-01', weekCount: 18);

    expect(bodies.length, 1, reason: '校历解析不该靠重试兜底，首请求就要关思考');
    expect(bodies.single['thinking'], {'type': 'disabled'});
    expect(bodies.single['model'], 'deepseek-flash');
    expect(rules.map((r) => r.date), ['2026-10-01']);
  });

  group('chat（纯文本对话，拓展 ai.chat 接口的底层）', () {
    test('文本请求：user content 是字符串（不是识图那种分段数组），system 在前', () async {
      await configured();
      final bodies = stub([reply('你好', 'stop')]);

      final out = await AiVision.I.chat('问个问题', system: '你是助手', maxTokens: 512);

      expect(out, '你好');
      final msgs = bodies.single['messages'] as List;
      expect(msgs.length, 2);
      expect(msgs.first, {'role': 'system', 'content': '你是助手'});
      expect(msgs.last, {'role': 'user', 'content': '问个问题'});
      expect(jsonEncode(bodies.single).contains('image_url'), isFalse);
      expect(bodies.single['max_tokens'], 512);
    });

    test('首次空回答：自动关思考重试一次（与识图同一套兜底）', () async {
      await configured();
      final bodies = stub([reply('', 'length'), reply('答出来了', 'stop')]);

      final out = await AiVision.I.chat('x');

      expect(out, '答出来了');
      expect(bodies.length, 2);
      expect(bodies.first.containsKey('thinking'), isFalse);
      expect(bodies.last['thinking'], {'type': 'disabled'});
    });

    test('没配置模型：报「尚未配置」并指向 AI 设置', () async {
      // 单例是进程级的：前面的用例已 configured()，这里显式存一份「关着」的配置
      await AiVision.I
          .save(AiConfig(enabled: false, providerId: 'deepseek', model: '')..setApiKey(''));
      await expectLater(
        AiVision.I.chat('x'),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('AI 设置'))),
      );
    });
  });

  group('chatWithTools（拓展工坊 Agent 的底层）', () {
    Map<String, dynamic> toolReply(String name, String args, {String id = 'call_1'}) => {
          'choices': [
            {
              'message': {
                'content': '',
                'tool_calls': [
                  {
                    'id': id,
                    'type': 'function',
                    'function': {'name': name, 'arguments': args},
                  }
                ],
              },
              'finish_reason': 'tool_calls',
            }
          ],
        };

    const spec = AiToolSpec(
      name: 'write_file',
      description: '写一个文件',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'content': {'type': 'string'},
        },
        'required': ['path', 'content'],
      },
    );

    test('原生工具调用：请求带 tools / tool_choice，回复解析出 name 与参数', () async {
      await configured();
      final bodies = stub([toolReply('write_file', '{"path":"main.js","content":"x"}')]);

      final reply = await AiVision.I.chatWithTools(
        [AiChatMessage.system('你是拓展工坊'), AiChatMessage.user('写个页面')],
        tools: const [spec],
      );

      expect(reply.usedTools, isTrue);
      expect(reply.toolCalls.single.name, 'write_file');
      expect(reply.toolCalls.single.id, 'call_1');
      expect(jsonDecode(reply.toolCalls.single.argumentsJson)['path'], 'main.js');
      expect(bodies.single['tool_choice'], 'auto');
      expect((bodies.single['tools'] as List).single['function']['name'], 'write_file');
    });

    test('多轮：assistant 的 tool_calls 与 tool 结果按协议回传', () async {
      await configured();
      final bodies = stub([reply('好了', 'stop')]);

      await AiVision.I.chatWithTools([
        AiChatMessage.system('s'),
        AiChatMessage.user('u'),
        AiChatMessage.assistant('', toolCalls: const [
          AiToolCall(id: 'call_9', name: 'read_file', argumentsJson: '{"path":"main.js"}'),
        ]),
        AiChatMessage.tool('call_9', '文件内容'),
      ], tools: const [spec]);

      final msgs = bodies.single['messages'] as List;
      expect(msgs[2]['role'], 'assistant');
      expect(msgs[2]['tool_calls'][0]['id'], 'call_9');
      expect(msgs[2]['tool_calls'][0]['function']['name'], 'read_file');
      expect(msgs[3], {'role': 'tool', 'content': '文件内容', 'tool_call_id': 'call_9'});
    });

    test('提供商不认 tools：自动去掉 tools 重试，标记 usedTools=false', () async {
      await configured();
      final bodies = <Map<String, dynamic>>[];
      AiVision.clientOverride = MockClient((req) async {
        bodies.add(jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>);
        if (bodies.length == 1) {
          return http.Response('{"error":"tools unsupported"}', 400);
        }
        return http.Response.bytes(utf8.encode(jsonEncode(reply('好的', 'stop'))), 200);
      });

      final out = await AiVision.I.chatWithTools(
        [AiChatMessage.user('x')],
        tools: const [spec],
      );

      expect(out.text, '好的');
      expect(out.usedTools, isFalse);
      expect(bodies.length, 2);
      expect(bodies.first['tools'], isNotEmpty);
      expect(bodies.last.containsKey('tools'), isFalse);
    });

    test('空回复带 tools 也先关思考重试，不丢 tools', () async {
      await configured();
      final bodies = stub([
        reply('', 'length'),
        toolReply('write_file', '{"path":"a.js","content":"x"}'),
      ]);

      final out = await AiVision.I.chatWithTools(
        [AiChatMessage.user('x')],
        tools: const [spec],
      );

      expect(out.toolCalls, hasLength(1));
      expect(bodies.length, 2);
      expect(bodies.last['thinking'], {'type': 'disabled'});
      expect(bodies.last['tools'], isNotEmpty);
    });

    test('流式：推理 / 正文 / 工具参数碎片分别累积，最终回复完整', () async {
      await configured();
      final bodies = <Map<String, dynamic>>[];
      final chunks = [
        {
          'choices': [
            {'delta': {'reasoning_content': '先想'}}
          ]
        },
        {
          'choices': [
            {'delta': {'content': '你'}}
          ]
        },
        {
          'choices': [
            {'delta': {'content': '好'}}
          ]
        },
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_s',
                    'function': {'name': 'read_file', 'arguments': '{"path"'},
                  }
                ]
              }
            }
          ]
        },
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': ':"main.js"}'},
                  }
                ]
              },
              'finish_reason': 'tool_calls',
            }
          ]
        },
      ];
      final sse = '${chunks.map((c) => 'data: ${jsonEncode(c)}\n\n').join()}data: [DONE]\n\n';
      AiVision.clientOverride = MockClient.streaming((req, bodyStream) async {
        bodies.add(jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>);
        return http.StreamedResponse(
          Stream.fromIterable([utf8.encode(sse)]),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final text = <String>[];
      final reasoning = <String>[];
      final out = await AiVision.I.chatWithToolsStream(
        [AiChatMessage.user('x')],
        tools: const [spec],
        onText: text.add,
        onReasoning: reasoning.add,
      );

      expect(bodies.single['stream'], isTrue);
      expect(reasoning.join(), '先想');
      expect(text.join(), '你好');
      expect(out.text, '你好');
      expect(out.reasoning, '先想');
      expect(out.toolCalls.single.name, 'read_file');
      expect(out.toolCalls.single.argumentsJson, '{"path":"main.js"}');
      expect(out.finishReason, 'tool_calls');
    });
  });
}
