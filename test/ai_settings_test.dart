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
      expect(aiProviderById('nope'), isNull);
    });

    test('已移除 Claude 提供商（统一走 OpenAI 兼容接口）', () {
      expect(aiProviderById('claude'), isNull);
      expect(aiProviders.any((p) => p.id == 'claude'), isFalse);
    });

    test('自定义提供商才需要用户填 Base URL', () {
      expect(aiProviderById('custom')!.isCustom, isTrue);
      for (final p in aiProviders.where((p) => p.id != 'custom')) {
        expect(p.isCustom, isFalse, reason: '${p.id} 用注册表地址，界面不给填');
        expect(p.baseUrl, isNotEmpty);
      }
    });
  });

  group('AI 配置', () {
    test('JSON 往返', () {
      final c = AiConfig(
        enabled: true,
        providerId: 'glm',
        model: 'glm-4.6',
        customBaseUrl: 'https://proxy.example/v1',
      )..setApiKey('sk-test');
      final back = AiConfig.decode(AiConfig.encode(c));
      expect(back.enabled, isTrue);
      expect(back.providerId, 'glm');
      expect(back.apiKey, 'sk-test');
      expect(back.model, 'glm-4.6');
      expect(back.summary, 'GLM（智谱 AI） · glm-4.6');
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
          enabled: true, providerId: 'custom', model: 'm',
          customBaseUrl: 'https://my.host/v1')..setApiKey('k');
      expect(c.baseUrl, 'https://my.host/v1');
      expect(c.ready, isTrue);

      expect((c.copy()..enabled = false).ready, isFalse, reason: '没开启就不算就绪');
      final noKey = c.copy()..keys = {};
      expect(noKey.ready, isFalse, reason: '没 Key 不算就绪');
      expect((c.copy()..model = '').ready, isFalse, reason: '没模型不算就绪');

      final noBase = AiConfig(enabled: true, providerId: 'custom', model: 'm')..setApiKey('k');
      expect(noBase.ready, isFalse, reason: '自定义提供商没填地址不算就绪');
    });
  });

  group('开发期临时 Key（仅本机 prefs，不进仓库）', () {
    test('调试 Key 不能让空配置变成就绪（开关/模型/地址仍必需）', () {
      final c = AiConfig(providerId: 'deepseek', model: 'deepseek-v4-flash')
        ..debugApiKey = 'sk-debug';
      expect(c.effectiveApiKey, 'sk-debug');
      expect(c.ready, isFalse, reason: '没启用就不能算就绪');

      final on = AiConfig(enabled: true, providerId: 'deepseek', model: 'deepseek-v4-flash')
        ..debugApiKey = 'sk-debug';
      expect(on.ready, isTrue, reason: '启用 + 模型 + 默认地址 + 调试 Key 就够了');
    });

    test('用户自己填的 Key 优先于调试 Key', () {
      final c = AiConfig(enabled: true, providerId: 'deepseek', model: 'deepseek-v4-flash')
        ..setApiKey('sk-mine')
        ..debugApiKey = 'sk-debug';
      expect(c.effectiveApiKey, 'sk-mine');
      // 调试 Key 不参与 JSON 持久化（避免随手被同步/导出）
      expect(AiConfig.encode(c), isNot(contains('sk-debug')));
    });

    test('保存表单不会冲掉已有调试 Key（曾致「测试连接」报请先填写 API Key）', () async {
      await AiVision.I.save(
        AiConfig(enabled: true, providerId: 'deepseek', model: 'm')..debugApiKey = 'sk-keep',
        touchDebugKey: true,
      );
      expect(AiVision.I.config.effectiveApiKey, 'sk-keep');

      // 模拟设置页保存草稿：草稿里没有调试 Key
      await AiVision.I.save(AiConfig(enabled: true, providerId: 'deepseek', model: 'm2'));
      expect(AiVision.I.config.effectiveApiKey, 'sk-keep', reason: '应沿用内存里的调试 Key');
      expect(AiVision.I.config.model, 'm2');
    });

    test('显式清空调试 Key 时不会又被填回来', () async {
      await AiVision.I.save(
        AiConfig(enabled: true, providerId: 'deepseek', model: 'm')..debugApiKey = 'sk-keep',
        touchDebugKey: true,
      );
      await AiVision.I.save(
        AiConfig(enabled: true, providerId: 'deepseek', model: 'm'),
        touchDebugKey: true, // 显式管理且为空 = 清除
      );
      expect(AiVision.I.config.debugApiKey, isEmpty);
      expect(AiVision.I.config.effectiveApiKey, isEmpty);
      await AiVision.I.load();
      expect(AiVision.I.config.debugApiKey, isEmpty, reason: '重载后也不该复活');
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
