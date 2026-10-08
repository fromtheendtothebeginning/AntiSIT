import 'dart:convert';

/// AI 提供商注册表：与 index 仓库的 `backend/aisettings.py` / `src/utils/aiProviders.js` 保持同步。
/// [api] 决定请求形状：`openai` = OpenAI 兼容 /chat/completions（Bearer），
/// `anthropic` = Anthropic /v1/messages（x-api-key）。
class AiProvider {
  const AiProvider({
    required this.id,
    required this.label,
    required this.desc,
    required this.baseUrl,
    required this.api,
    this.models = const [],
    this.defaultModel = '',
    this.docs = '',
  });

  final String id;
  final String label;
  final String desc;
  final String baseUrl;
  final String api;
  final List<String> models;
  final String defaultModel;
  final String docs;

  bool get needsBaseUrl => baseUrl.isEmpty; // 自定义提供商必须自己填地址
}

const List<AiProvider> aiProviders = [
  AiProvider(
    id: 'deepseek',
    label: 'DeepSeek',
    desc: 'deepseek.com（官方）',
    baseUrl: 'https://api.deepseek.com',
    api: 'openai',
    models: ['deepseek-v4-flash', 'deepseek-v4-pro', 'deepseek-v4-flash-vision-exp'],
    defaultModel: 'deepseek-v4-flash',
    docs: 'https://platform.deepseek.com/api_keys',
  ),
  AiProvider(
    id: 'opencode-go',
    label: 'OpenCode Go',
    desc: 'opencode.ai 聚合订阅',
    baseUrl: 'https://opencode.ai/zen/go/v1',
    api: 'openai',
    models: [
      'deepseek-v4-flash', 'deepseek-v4-pro', 'deepseek-v4-flash-vision-exp',
      'glm-5.3', 'glm-5.2', 'glm-5.1', 'kimi-k3', 'kimi-k2.7-code', 'kimi-k2.6',
      'mimo-v2.5', 'mimo-v2.5-pro', 'qwen3.8-max', 'qwen3.7-max', 'qwen3.7-plus',
      'qwen3.6-plus', 'grok-4.5', 'gpt-5.6-luna', 'minimax-m3', 'minimax-m2.7',
      'hy3', 'ox-alpha-free',
    ],
    defaultModel: 'deepseek-v4-flash',
    docs: 'https://opencode.ai/docs/go/',
  ),
  AiProvider(
    id: 'kimi',
    label: 'Kimi（月之暗面）',
    desc: 'moonshot.cn',
    baseUrl: 'https://api.moonshot.cn/v1',
    api: 'openai',
    models: ['kimi-k3', 'kimi-k2.7-code', 'kimi-k2.7-code-highspeed', 'kimi-k2.6', 'kimi-k2.5'],
    defaultModel: 'kimi-k3',
  ),
  AiProvider(
    id: 'glm',
    label: 'GLM（智谱）',
    desc: 'bigmodel.cn',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    api: 'openai',
    models: ['glm-5.3', 'glm-5.2', 'glm-5.1', 'glm-4.7', 'glm-4.7-flash', 'glm-4.6', 'glm-4.5-air'],
    defaultModel: 'glm-4.6',
  ),
  AiProvider(
    id: 'qwen',
    label: 'Qwen（通义）',
    desc: 'dashscope 兼容模式',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    api: 'openai',
    models: ['qwen3.8-max', 'qwen3.7-max', 'qwen3.7-plus', 'qwen3.6-plus', 'qwen-max', 'qwen-plus', 'qwen-turbo'],
    defaultModel: 'qwen-max',
  ),
  AiProvider(
    id: 'claude',
    label: 'Claude',
    desc: 'Anthropic（走 /v1/messages）',
    baseUrl: 'https://api.anthropic.com',
    api: 'anthropic',
    models: ['claude-opus-5', 'claude-opus-4-8', 'claude-sonnet-5', 'claude-sonnet-4-6', 'claude-haiku-4-5'],
    defaultModel: 'claude-sonnet-5',
  ),
  AiProvider(
    id: 'gpt',
    label: 'GPT',
    desc: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    api: 'openai',
    models: ['gpt-5', 'gpt-5-mini', 'gpt-5-nano', 'gpt-4.1', 'gpt-4.1-mini', 'gpt-4o'],
    defaultModel: 'gpt-5-mini',
  ),
  AiProvider(
    id: 'gemini',
    label: 'Gemini',
    desc: 'Google（OpenAI 兼容层）',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    api: 'openai',
    models: ['gemini-3.7-flash', 'gemini-3.5-flash-lite', 'gemini-3.1-pro-preview', 'gemini-2.5-pro', 'gemini-2.5-flash'],
    defaultModel: 'gemini-2.5-flash',
  ),
  AiProvider(
    id: 'mimo',
    label: 'MiMo',
    desc: '小米',
    baseUrl: 'https://api.xiaomimimo.com/v1',
    api: 'openai',
    models: ['mimo-v2.5', 'mimo-v2.5-pro'],
    defaultModel: 'mimo-v2.5',
  ),
  AiProvider(
    id: 'custom',
    label: '自定义（OpenAI 兼容）',
    desc: '自填 Base URL，任何 OpenAI 兼容服务',
    baseUrl: '',
    api: 'openai',
    models: [],
    defaultModel: '',
  ),
];

AiProvider? aiProviderById(String id) {
  for (final p in aiProviders) {
    if (p.id == id) return p;
  }
  return null;
}

/// AI 配置（本机保存；仅用于识图，如自动识别验证码 / 校历调休）。
/// 与网站在「我的 → AI 设置」里配的是同一套参数，只是 App 直连模式不经服务器、要自己调 AI。
class AiConfig {
  AiConfig({
    this.enabled = false,
    this.providerId = 'deepseek',
    this.apiKey = '',
    this.model = '',
    this.customBaseUrl = '',
  });

  /// 是否启用 AI 识别（关闭则一律手动输验证码 / 手动填调休）。
  bool enabled;
  String providerId;
  String apiKey;
  String model;

  /// 覆盖提供商默认地址（自定义提供商必填）。
  String customBaseUrl;

  AiProvider get provider => aiProviderById(providerId) ?? aiProviders.first;

  /// 实际请求用的 Base URL。
  String get baseUrl =>
      customBaseUrl.trim().isNotEmpty ? customBaseUrl.trim() : provider.baseUrl;

  /// 是否已配好（能发起请求）。
  bool get ready => enabled && apiKey.trim().isNotEmpty && model.trim().isNotEmpty && baseUrl.isNotEmpty;

  /// 用于「测试连接」/识图的简况文案。
  String get summary => '${provider.label} · ${model.isEmpty ? '未选模型' : model}';

  AiConfig copy() => AiConfig(
        enabled: enabled,
        providerId: providerId,
        apiKey: apiKey,
        model: model,
        customBaseUrl: customBaseUrl,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'providerId': providerId,
        'apiKey': apiKey,
        'model': model,
        'customBaseUrl': customBaseUrl,
      };

  static AiConfig fromJson(Map<String, dynamic>? j) {
    if (j == null) return AiConfig();
    return AiConfig(
      enabled: j['enabled'] == true,
      providerId: (j['providerId'] ?? 'deepseek').toString(),
      apiKey: (j['apiKey'] ?? '').toString(),
      model: (j['model'] ?? '').toString(),
      customBaseUrl: (j['customBaseUrl'] ?? '').toString(),
    );
  }

  static String encode(AiConfig c) => jsonEncode(c.toJson());

  static AiConfig decode(String? raw) {
    if (raw == null || raw.isEmpty) return AiConfig();
    try {
      final j = jsonDecode(raw);
      return fromJson(j is Map ? j.cast<String, dynamic>() : null);
    } catch (_) {
      return AiConfig();
    }
  }
}
