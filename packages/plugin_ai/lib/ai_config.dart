import 'dart:convert';

import 'package:campus_core/campus_core.dart';

/// AI 配置（本机保存）：统一走 OpenAI 兼容接口。
/// [keys] 按提供商分别保存——换提供商不用重填，也不会拿 A 家的 Key 去请求 B 家。
///
/// **提供商本身不在这个包/文件里**：一家一个插件包（`packages/plugin_ai_xxx/`），
/// 通过 [PluginRegistry] 注册；这里只按 id 解析（见 [provider]）。
/// 加一家 = 加一个包 + 宿主 pubspec 一行 + `dart run tool/gen_plugins.dart`。
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

  /// 当前提供商：存着的 id 没装（插件包被删 / 被 EXCLUDE）时回退到第一个装了的，
  /// 一个都没有就用兜底（基址为空 → [ready] 为假，界面表现为「未配置」）。
  AiProviderPlugin get provider => PluginRegistry.I.resolveProvider(providerId);

  /// 配置里的提供商是否可用：**装着且没被停用**。不可用就不能发请求——不然 `provider`
  /// 已回退到别家，而 [apiKey] 还是这家 id 的 Key，会把 A 家的 Key 发到 B 家的域名。
  /// 注册表还没装配（空表，如纯单测 / 极早启动）时不判。
  bool get providerUsable {
    final all = PluginRegistry.I.providers;
    return all.isEmpty || PluginRegistry.I.isProviderEnabled(providerId);
  }

  /// 当前提供商的 Key。
  String get apiKey => (keys[providerId] ?? '').trim();

  String setApiKey(String v) => keys[providerId] = v.trim();

  /// 实际请求用的 Base URL：自定义用填的，其余用注册表里那家的。
  String get baseUrl => provider.isCustom ? customBaseUrl.trim() : provider.baseUrl;

  /// 实际发请求用的 API Key：优先用用户填的；debug 构建下若本机存了开发期临时 Key
  /// （`ai_debug_api_key`，由 `AiVision.load` 读入），且用户没填，就用它——
  /// 这样临时 Key 不必写进仓库（仓库是公开的）。release 构建永远不读该字段。
  String get effectiveApiKey => apiKey.isNotEmpty ? apiKey : debugApiKey.trim();

  /// 开发期临时 Key（仅 debug 构建由 AiVision 注入，release 恒为空）。
  String debugApiKey = '';

  /// 是否已配好（能发起请求）。
  bool get ready =>
      enabled &&
      providerUsable &&
      effectiveApiKey.isNotEmpty &&
      model.trim().isNotEmpty &&
      baseUrl.isNotEmpty;

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
