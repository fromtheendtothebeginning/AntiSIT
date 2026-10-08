import 'dart:convert';

/// AI 提供商注册表：与 index 仓库的 `backend/aisettings.py` / `src/utils/aiProviders.js` 同步。
/// 全部走 OpenAI 兼容接口（`{base}/chat/completions`、`GET {base}/models`，Bearer 鉴权）。
class AiProvider {
  const AiProvider({
    required this.id,
    required this.label,
    required this.desc,
    required this.baseUrl,
    this.models = const [],
    this.defaultModel = '',
    this.docs = '',
  });

  final String id;
  final String label;
  final String desc;
  final String baseUrl;
  final List<String> models;
  final String defaultModel;
  final String docs;

  /// 自定义提供商：由用户填 Base URL。
  bool get isCustom => baseUrl.isEmpty;
}

const List<AiProvider> aiProviders = [
  AiProvider(
    id: 'deepseek',
    label: 'DeepSeek',
    desc: '知名推理模型，Vision 需选 *-vision-exp',
    baseUrl: 'https://api.deepseek.com',
    models: ['deepseek-v4-flash', 'deepseek-v4-pro', 'deepseek-v4-flash-vision-exp'],
    defaultModel: 'deepseek-v4-flash',
    docs: 'https://platform.deepseek.com/api_keys',
  ),
  AiProvider(
    id: 'opencode-go',
    label: 'OpenCode Go',
    desc: '聚合订阅，一个 Key 用多家模型',
    baseUrl: 'https://opencode.ai/zen/go/v1',
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
    desc: 'K3/K2.6 支持读图',
    baseUrl: 'https://api.moonshot.cn/v1',
    models: ['kimi-k3', 'kimi-k2.7-code', 'kimi-k2.7-code-highspeed', 'kimi-k2.6', 'kimi-k2.5'],
    defaultModel: 'kimi-k3',
  ),
  AiProvider(
    id: 'glm',
    label: 'GLM（智谱）',
    desc: '识图用 GLM-4V 系列',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    models: ['glm-5.3', 'glm-5.2', 'glm-5.1', 'glm-4.7', 'glm-4.7-flash', 'glm-4.6', 'glm-4.5-air'],
    defaultModel: 'glm-4.6',
  ),
  AiProvider(
    id: 'qwen',
    label: 'Qwen（通义）',
    desc: '百炼兼容模式，qwen-vl 系列读图',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    models: ['qwen3.8-max', 'qwen3.7-max', 'qwen3.7-plus', 'qwen3.6-plus', 'qwen-max', 'qwen-plus', 'qwen-turbo'],
    defaultModel: 'qwen-max',
  ),
  AiProvider(
    id: 'gpt',
    label: 'GPT',
    desc: 'OpenAI 官方，gpt-4o/gpt-5 可读图',
    baseUrl: 'https://api.openai.com/v1',
    models: ['gpt-5', 'gpt-5-mini', 'gpt-5-nano', 'gpt-4.1', 'gpt-4.1-mini', 'gpt-4o'],
    defaultModel: 'gpt-5-mini',
  ),
  AiProvider(
    id: 'gemini',
    label: 'Gemini',
    desc: 'Google（OpenAI 兼容层），原生多模态',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    models: ['gemini-3.7-flash', 'gemini-3.5-flash-lite', 'gemini-3.1-pro-preview', 'gemini-2.5-pro', 'gemini-2.5-flash'],
    defaultModel: 'gemini-2.5-flash',
  ),
  AiProvider(
    id: 'mimo',
    label: 'MiMo',
    desc: '小米',
    baseUrl: 'https://api.xiaomimimo.com/v1',
    models: ['mimo-v2.5', 'mimo-v2.5-pro'],
    defaultModel: 'mimo-v2.5',
  ),
  AiProvider(
    id: 'custom',
    label: '自定义',
    desc: '自填 Base URL 与模型 ID',
    baseUrl: '',
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

/// 可读图的模型特征（照抄 index `backend/constants.py: VISION_MODEL_PATTERNS`）。
/// 用于把模型列表按「能不能识图」筛一遍——选错模型会返回空内容再回退手输，很难排查。
const List<String> visionModelPatterns = [
  'vision', 'multimodal', 'gemini', 'gpt-4o', 'gpt-4-vision', 'gpt-5',
  'grok', 'minimax-m3', 'minimax-vl', 'kimi', 'mimo',
  'qwen3.8', 'qwen3.7',
  'qwen3.5-omni', 'qwen-vl', 'qwen2.5-vl', '-vl', '4v', 'internvl',
  'glm-5v', 'glm-4v', 'glm-ocr',
];

bool looksLikeVisionModel(String modelId) {
  final m = modelId.toLowerCase();
  return visionModelPatterns.any((p) => m.contains(p.toLowerCase()));
}

/// AI 配置（本机保存）：统一走 OpenAI 兼容接口。
/// [keys] 按提供商分别保存——换提供商不用重填，也不会拿 A 家的 Key 去请求 B 家。
class AiConfig {
  AiConfig({
    this.enabled = false,
    this.providerId = 'deepseek',
    this.model = '',
    this.customBaseUrl = '',
    Map<String, String>? keys,
  }) : keys = keys ?? {};

  /// 是否启用 AI 识别（关闭则一律手动输验证码 / 手动填调休）。
  bool enabled;
  String providerId;
  String model;

  /// 自定义提供商专用（其他提供商一律用注册表里的地址，界面不给填）。
  String customBaseUrl;

  /// providerId → API Key。
  Map<String, String> keys;

  AiProvider get provider => aiProviderById(providerId) ?? aiProviders.first;

  /// 当前提供商的 Key。
  String get apiKey => (keys[providerId] ?? '').trim();

  String setApiKey(String v) => keys[providerId] = v.trim();

  /// 实际请求用的 Base URL：自定义用填的，其余用注册表默认。
  String get baseUrl => provider.isCustom ? customBaseUrl.trim() : provider.baseUrl;

  /// 实际发请求用的 API Key：优先用用户填的；debug 构建下若本机存了开发期临时 Key
  /// （`ai_debug_api_key`，由 `AiVision.load` 读入），且用户没填，就用它——
  /// 这样临时 Key 不必写进仓库（仓库是公开的）。release 构建永远不读该字段。
  String get effectiveApiKey => apiKey.isNotEmpty ? apiKey : debugApiKey.trim();

  /// 开发期临时 Key（仅 debug 构建由 AiVision 注入，release 恒为空）。
  String debugApiKey = '';

  /// 是否已配好（能发起请求）。
  bool get ready =>
      enabled && effectiveApiKey.isNotEmpty && model.trim().isNotEmpty && baseUrl.isNotEmpty;

  String get summary => '${provider.label} · ${model.isEmpty ? '未选模型' : model}';

  /// 复制（含调试 Key，便于测试连接时仍能用到临时 Key）。
  AiConfig copy() {
    final c = AiConfig(
      enabled: enabled,
      providerId: providerId,
      model: model,
      customBaseUrl: customBaseUrl,
      keys: Map<String, String>.from(keys),
    );
    return c..debugApiKey = debugApiKey;
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'providerId': providerId,
        'model': model,
        'customBaseUrl': customBaseUrl,
        'keys': keys,
      };

  static AiConfig fromJson(Map<String, dynamic>? j) {
    if (j == null) return AiConfig();
    return AiConfig(
      enabled: j['enabled'] == true,
      providerId: (j['providerId'] ?? 'deepseek').toString(),
      model: (j['model'] ?? '').toString(),
      customBaseUrl: (j['customBaseUrl'] ?? '').toString(),
      keys: (j['keys'] is Map)
          ? (j['keys'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
          : {},
    );
  }

  static String encode(AiConfig c) => jsonEncode(c.toJson());

  static AiConfig decode(String? raw) {
    if (raw == null || raw.isEmpty) return AiConfig();
    try {
      final j = jsonDecode(raw);
      final c = fromJson(j is Map ? j.cast<String, dynamic>() : null);
      // 兼容早期单 Key 版本（apiKey 字段）：迁移到当前提供商名下
      if (j is Map && j['apiKey'] is String && (j['apiKey'] as String).trim().isNotEmpty) {
        c.keys.putIfAbsent(c.providerId, () => (j['apiKey'] as String).trim());
      }
      return c;
    } catch (_) {
      return AiConfig();
    }
  }
}
