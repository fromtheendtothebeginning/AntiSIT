import 'dart:typed_data';

import 'package:campus_service/ai/ai_settings.dart';import 'package:campus_service/ai/ai_tasks.dart';
import 'package:campus_service/ai/ai_vision.dart';
import 'package:campus_service/api_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 设置（直连模式下 App 自己调 AI 识图：自动识别验证码、识别校历调休）。
/// 这里覆盖纯逻辑部分：配置读写、提供商注册表、模型输出解析、未配置时的报错。
/// 真实调用 AI 要联网+Key，不在单测里做。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('提供商注册表', () {
    test('每个提供商 id 唯一，且能找到默认模型', () {
      final ids = aiProviders.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'id 不能重复');
      for (final p in aiProviders) {
        if (p.id == 'custom') {
          expect(p.baseUrl, isEmpty, reason: '自定义提供商要用户自己填地址');
          continue;
        }
        expect(p.baseUrl, isNotEmpty, reason: '${p.id} 应有默认地址');
        expect(p.models, contains(p.defaultModel), reason: '${p.id} 默认模型应在列表里');
      }
    });

    test('按 id 取提供商；未知 id 取不到（由 AiConfig 兜底）', () {
      expect(aiProviderById('deepseek')?.label, 'DeepSeek');
      expect(aiProviderById('claude')?.api, 'anthropic', reason: 'Claude 走 /v1/messages');
      expect(aiProviderById('nope'), isNull);
    });
  });

  group('AI 配置', () {
    test('JSON 往返', () {
      final c = AiConfig(
        enabled: true,
        providerId: 'glm',
        apiKey: 'sk-test',
        model: 'glm-4.6',
        customBaseUrl: 'https://proxy.example/v1',
      );
      final back = AiConfig.decode(AiConfig.encode(c));
      expect(back.enabled, isTrue);
      expect(back.providerId, 'glm');
      expect(back.apiKey, 'sk-test');
      expect(back.model, 'glm-4.6');
      expect(back.summary, 'GLM（智谱） · glm-4.6');
    });

    test('缺字段/坏数据回落到默认值，不抛异常', () {
      final d = AiConfig.decode(null);
      expect(d.enabled, isFalse);
      expect(d.providerId, 'deepseek');
      expect(d.ready, isFalse);
      expect(AiConfig.decode('{oops').providerId, 'deepseek');
    });

    test('自定义 Base URL 覆盖提供商默认；ready 需四项齐备', () {
      final c = AiConfig(
          enabled: true, providerId: 'custom', apiKey: 'k', model: 'm',
          customBaseUrl: 'https://my.host/v1');
      expect(c.baseUrl, 'https://my.host/v1');
      expect(c.ready, isTrue);

      expect((c.copy()..enabled = false).ready, isFalse, reason: '没开启就不算就绪');
      expect((c.copy()..apiKey = '  ').ready, isFalse, reason: '没 Key 不算就绪');
      expect((c.copy()..model = '').ready, isFalse, reason: '没模型不算就绪');

      final noBase = AiConfig(enabled: true, providerId: 'custom', apiKey: 'k', model: 'm');
      expect(noBase.ready, isFalse, reason: '自定义提供商没填地址不算就绪');
    });
  });

  group('识图调用', () {
    test('未配置时抛可读错误（引导去 AI 设置）', () async {
      await AiVision.I.save(AiConfig()); // 未启用
      expect(AiVision.I.available, isFalse);
      await expectLater(
        () => AiVision.I.describeImage(Uint8List(0), prompt: 'x'),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('AI 设置'))),
      );
    });

    test('未配置时自动识别码直接放弃（返回 null，走手动输入）', () async {
      await AiVision.I.save(AiConfig());
      expect(await solveCaptcha(Uint8List(0)), isNull);
    });
  });

  group('校历 JSON 解析', () {
    test('纯 JSON 数组', () {
      final r = extractJsonArray('[{"date":"2026-10-01","type":"off"}]');
      expect(r.length, 1);
      expect((r.first as Map)['type'], 'off');
    });

    test('被 ```json 代码块包裹 / 前后带解释也能抠出来', () {
      const wrapped = '好的，结果如下：\n```json\n[{"date":"2026-10-01","type":"off"}]\n```\n以上。';
      expect(extractJsonArray(wrapped).length, 1);
      expect(extractJsonArray('说明文字 [ ] 结尾').length, 0);
    });

    test('不是数组/解析失败时返回空，不抛异常', () {
      expect(extractJsonArray('{"a":1}'), isEmpty);
      expect(extractJsonArray('完全不是 JSON'), isEmpty);
      expect(extractJsonArray(''), isEmpty);
    });
  });
}
