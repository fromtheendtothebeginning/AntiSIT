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
}
