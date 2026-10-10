import 'package:campus_core/campus_core.dart';
import 'package:campus_service/plugins/bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ai/plugin_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 设置（直连模式下 App 自己调 AI 识图：自动识别验证码、识别校历调休）。
/// 这里覆盖纯逻辑部分：配置读写、提供商注册表、模型输出解析、未配置时的报错。
/// 真实调用 AI 要联网+Key，不在单测里做。
void main() {
  /// 提供商从插件注册表来（一家一个包，见 packages/plugin_ai_*）；
  /// AiConfig / AiVision / 设置页都走全局注册表，所以这里先把它装成真实清单。
  late PluginRegistry reg;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    reg = buildAppRegistry();
    PluginRegistry.I = reg;
  });

  group('提供商注册表（一家一个插件包）', () {
    test('每个提供商 id 唯一，且能找到默认模型', () {
      expect(reg.providers, isNotEmpty);
      final ids = reg.providers.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'id 不能重复');
      for (final p in reg.providers) {
        if (p.isCustom) {
          expect(p.baseUrl, isEmpty, reason: '自定义提供商要用户自己填地址');
          continue;
        }
        expect(p.baseUrl, isNotEmpty, reason: '${p.id} 应有默认地址');
        expect(p.models, contains(p.defaultModel), reason: '${p.id} 默认模型应在列表里');
      }
    });

    test('按 id 取提供商；未知 id 取不到（由 AiConfig 兜底）', () {
      expect(reg.providerById('deepseek')?.label, 'DeepSeek');
      expect(reg.providerById('nope'), isNull);
    });

    test('已移除 Claude 提供商（统一走 OpenAI 兼容接口）', () {
      expect(reg.providerById('claude'), isNull);
      expect(reg.providers.any((p) => p.id == 'claude'), isFalse);
    });

    test('自定义提供商才需要用户填 Base URL，且排在选单最后', () {
      expect(reg.providerById('custom')!.isCustom, isTrue);
      for (final p in reg.providers.where((p) => !p.isCustom)) {
        expect(p.isCustom, isFalse, reason: '${p.id} 用注册表地址，界面不给填');
        expect(p.baseUrl, isNotEmpty);
      }
      expect(reg.providerChoices.last.id, 'custom', reason: '自定义是兜底入口，排最后');
    });

    test('除自定义外都填了申请页——设置页的「申请 API Key」按钮靠它', () {
      for (final p in reg.providers.where((p) => !p.isCustom)) {
        expect(p.docs, isNotEmpty, reason: '${p.id} 缺 docs，按钮会整个消失');
        final uri = Uri.tryParse(p.docs);
        expect(uri?.hasScheme, isTrue, reason: '${p.id} 的 docs 不是合法链接：${p.docs}');
        expect(uri?.host, isNotEmpty);
      }
      expect(reg.providerById('custom')!.docs, isEmpty, reason: '自定义没有开放平台可跳');
    });

    test('每个提供商的说明与 logo 都在自己包里（删包即连图标一起消失）', () {
      for (final p in reg.providers) {
        expect(p.description, isNotEmpty, reason: '${p.id} 缺说明，管理页列表会空一行');
        expect(p.logo, startsWith('packages/'),
            reason: '${p.id} 的 logo 应指向自己包里的资产，而不是宿主 assets/');
        expect(p.applyLabel, isNotEmpty, reason: '${p.id} 缺按钮文案');
      }
    });

    test('MiniMax / MiMo 订阅：地址、默认模型、申请页都对得上官网', () {
      final mini = reg.providerById('minimax');
      final miniPlan = reg.providerById('minimaxtokenplan');
      final mimoPlan = reg.providerById('mimotokenplan');
      if (mini == null || miniPlan == null || mimoPlan == null) {
        return; // 那家被删 / 被 EXCLUDE 掉了（删提供商包不用改测试）
      }
      expect(mini.baseUrl, 'https://api.minimax.cn/v1', reason: '国内站 .cn（国际是 api.minimax.io）');
      expect(mini.defaultModel, 'MiniMax-M3',
          reason: '识图只有 M3 系列；M2.x 是纯文本，两个功能都用不了');
      expect(mini.models, contains(mini.defaultModel));

      expect(miniPlan.baseUrl, mini.baseUrl, reason: '订阅与按量付费同一个域名，只靠 Key 区分');
      expect(miniPlan.models, ['MiniMax-M3.1-Flash-Preview'],
          reason: '订阅 Key 只能调套餐内模型（官方说明不可与按量 Key 互换）');
      expect(miniPlan.docs, contains('platform.minimax.cn'));

      expect(mimoPlan.baseUrl, 'https://token-plan-cn.xiaomimimo.com/v1',
          reason: '套餐走独立域名（cn/sgp/ams 三处）');
      expect(mimoPlan.defaultModel, 'mimo-v2.6-flash');
      expect(mimoPlan.models, isNot(contains('mimo-v2.6-pro-ultraspeed')),
          reason: 'ultraspeed 不含在套餐内');
    });

    test('MiMo 按量付费：默认模型已换成 v2.5 下架后的 v2.6', () {
      final p = reg.providerById('mimo');
      if (p == null) return;
      expect(p.baseUrl, 'https://api.xiaomimimo.com/v1');
      expect(p.models.any((m) => m.startsWith('mimo-v2.6')), isTrue);
      expect(p.defaultModel, 'mimo-v2.6-flash', reason: 'v2.5 系列 2026-10-21 下线');
    });

    test('每个提供商的 logo 都能被加载（资产搬迁漏文件就会红）', () async {
      for (final p in reg.providers) {
        expect(p.logo, isNotEmpty);
        await expectLater(rootBundle.load(p.logo), completes, reason: '${p.id} 的 ${p.logo}');
      }
    });

    test('存档里的提供商被删掉（悬空 providerId）：判成未配置，不拿别家地址发这家 Key', () {
      // claude 已经不在清单里（历史上存过它的 Key）——正是「那个包被删掉」的情形
      final c = AiConfig(enabled: true, providerId: 'claude', model: 'claude-sonnet-5')
        ..setApiKey('sk-claude');
      expect(c.providerUsable, isFalse, reason: '清单里没有 claude');
      expect(c.ready, isFalse, reason: '不能让 claude 的 Key 发到回退后的别家域名上');
      expect(c.apiKey, 'sk-claude', reason: 'Key 留着，等这家装回来还能用');
      expect(c.provider.label, 'DeepSeek', reason: '界面回退到第一个装着的（非自定义）提供商');

      // 注册表还没装配（空表）时不判——纯单测 / 极早启动
      PluginRegistry.I = PluginRegistry();
      expect(c.providerUsable, isTrue);
    });

    test('停用当前选中的提供商：算未配置，AI 退回来；重新启用即恢复', () async {
      final c = AiConfig(enabled: true, providerId: 'kimi', model: 'kimi-k3')
        ..setApiKey('sk-kimi');
      expect(c.providerUsable, isTrue);
      expect(c.ready, isTrue);

      await reg.setProviderEnabled('kimi', false);
      expect(c.providerUsable, isFalse, reason: '停用了就不能再用它发请求');
      expect(c.ready, isFalse, reason: '界面上表现为「未配置」');
      expect(c.apiKey, 'sk-kimi', reason: 'Key 留着，开回来就能继续用');
      expect(AiVision.applyThinkingOff('kimi', 'kimi-k3'), isEmpty,
          reason: '停用的提供商连关思考字段都不该参与');

      await reg.setProviderEnabled('kimi', true);
      expect(c.ready, isTrue);
    });
  });

  group('关闭思考要加的请求字段（照官网文档 / index 实测）', () {
    // (提供商 id, 模型, 该加的字段)。**装着的必须完全一致；没装的跳过**——
    // 删掉一家提供商包只需要动 pubspec，不用回来改测试。
    const cases = <(String, String, Map<String, dynamic>)>[
      ('deepseek', 'deepseek-flash', {
        'thinking': {'type': 'disabled'}
      }),
      ('kimi', 'kimi-k3', {'reasoning_effort': 'none'}), // k3 用 reasoning_effort
      ('kimi', 'kimi-k2.7-code', {
        'thinking': {'type': 'disabled'}
      }), // K2.x 用 thinking
      ('qwen', 'qwen-max', {'enable_thinking': false}),
      ('gpt', 'gpt-5-mini', {'reasoning_effort': 'none'}),
      ('gemini', 'gemini-2.5-flash', {'reasoning_effort': 'none'}),
      // MiMo 用 reasoning_effort：index 2026-09-10 实测 thinking{"type":"disabled"}
      // 虽被接受却会把结果弄错；套餐是同一套模型与协议。
      ('mimo', 'mimo-v2.6-flash', {'reasoning_effort': 'none'}),
      ('mimotokenplan', 'mimo-v2.6-flash', {'reasoning_effort': 'none'}),
      ('minimax', 'MiniMax-M3', {
        'thinking': {'type': 'disabled'}
      }),
      ('minimax', 'MiniMax-M2.7', {
        'thinking': {'type': 'disabled'}
      }), // M2.x 会被忽略，也是这个字段
      // M3.1 只支持 adaptive 思考：发 thinking=disabled 会直接 400，改用最浅的档位
      ('minimaxtokenplan', 'MiniMax-M3.1-Flash-Preview', {'reasoning_effort': 'low'}),
      // 协议不确定 / 由用户自填的：什么都不加
      ('opencode-go', 'anything', {}),
      ('glm', 'anything', {}),
      ('custom', 'anything', {}),
    ];

    test('装着的每家：关思考字段与官网文档 / index 实测一致', () {
      for (final (pid, model, want) in cases) {
        if (reg.providerById(pid) == null) continue; // 这家被删 / 被 EXCLUDE 掉了
        expect(AiVision.applyThinkingOff(pid, model), want, reason: '$pid / $model');
        for (final key in want.keys) {
          expect(AiVision.applyThinkingOff(pid, model).containsKey(key), isTrue);
        }
      }
    });

    test('没装的 id 一律不加字段（乱加会 400）', () {
      // 以前 switch 里还兜着 openai / google / dashscope 这些别名，现在协议随包走，
      // 注册表里没有的 id 就是「不加字段」。
      for (final pid in ['nope', 'openai', 'google', 'dashscope']) {
        expect(AiVision.applyThinkingOff(pid, 'anything'), isEmpty, reason: pid);
      }
    });
  });

  group('AI 设置页', () {
    // AiVision 是单例：每个用例都从「默认提供商 + 未启用」起步，免得互相串配置
    setUp(() => AiVision.I.save(AiConfig(providerId: 'deepseek')));

    /// 提供商列表有十几个，弹窗高度按屏幕算：测试窗口放大一点，免得要滚动才能点到 MiniMax。
    void useTallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('停用的提供商不出现在选择器里；当前那家被停用时给出提示', (tester) async {
      useTallScreen(tester);
      await reg.setProviderEnabled('kimi', false);
      // 存档里选的就是这家（刚从插件管理页停用掉）
      await AiVision.I.save(
          AiConfig(enabled: true, providerId: 'kimi', model: 'kimi-k3')..setApiKey('sk-k'));
      await tester.pumpWidget(const MaterialApp(home: AiSettingsPage()));
      await tester.pump();

      expect(find.textContaining('已被停用'), findsOneWidget, reason: '要告诉用户为什么 AI 不工作');
      expect(find.text('Kimi（月之暗面）（已停用）'), findsOneWidget);

      await tester.tap(find.text('Kimi（月之暗面）（已停用）'));
      await tester.pumpAndSettle();
      expect(find.text('Kimi（月之暗面）'), findsNothing, reason: '停用的不该出现在选择器里');
      expect(find.text('DeepSeek'), findsOneWidget, reason: '其余照常可选');
    });

    testWidgets('「申请 API Key」按钮：默认提供商就有，切到订阅套餐换成订阅文案', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(const MaterialApp(home: AiSettingsPage()));
      await tester.pump();

      expect(find.text('申请 API Key'), findsOneWidget);
      expect(find.text('platform.deepseek.com'), findsOneWidget, reason: '旁边标出跳到哪');

      // 换成 MiniMax Token Plan：同一套按钮，文案改成「订阅 M Plan」
      await tester.tap(find.text('DeepSeek'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MiniMax Token Plan'));
      await tester.pumpAndSettle();

      expect(find.text('订阅 M Plan'), findsOneWidget);
      expect(find.text('platform.minimax.cn'), findsOneWidget);
      expect(find.text('MiniMax-M3.1-Flash-Preview'), findsOneWidget,
          reason: '订阅的默认模型是套餐内那个');
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
