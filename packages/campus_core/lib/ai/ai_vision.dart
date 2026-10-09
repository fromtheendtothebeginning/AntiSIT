import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_error.dart';
import '../plugins/plugin.dart';
import '../plugins/registry.dart';
import 'ai_settings.dart';

/// 「AI 设置」插件的 id（见 lib/plugins/features/ai_plugin.dart）。
/// 这里用字面量而不是 import 那个文件：插件是可删的，基础设施不该依赖某个插件存在。
const String _aiPluginId = PluginIds.ai;

/// AI 识图（多模态对话）：直连模式下 App 自己调用户的 AI 服务，
/// 用于自动识别登录验证码、识别校历图片里的调休安排。
///
/// 与 index 后端 `deps.py: ai_vision_text` 对齐（统一走 OpenAI 兼容接口）：
/// - 对话：POST `{base}/chat/completions`，Bearer 鉴权，content 里放 image_url(data:)
/// - 模型列表：GET `{base}/models`（用当前 Key 拉真实可用模型，失败回退注册表内置列表）
/// - 关闭思考：按提供商写各自的「off」参数（见 [_thinkingOffPayload]，照抄 aisettings.apply_thinking）
class AiVision {
  AiVision._();
  static final AiVision I = AiVision._();

  static const _spKey = 'ai_config';
  static const _modelsCacheKey = 'ai_models_cache';

  /// 开发期临时 API Key 的本机存储键（不进仓库；仅 debug 构建读取）。
  static const _debugKeyPref = 'ai_debug_api_key';

  AiConfig _config = AiConfig();
  final Map<String, List<String>> _modelsCache = {};
  bool _loaded = false;

  AiConfig get config => _config;

  Future<AiConfig> load() async {
    if (_loaded) return _config;
    final sp = await SharedPreferences.getInstance();
    _config = AiConfig.decode(sp.getString(_spKey));
    // 开发期临时 Key：只存在本机 prefs、不进仓库，且仅 debug 构建读取。
    if (kDebugMode) _config.debugApiKey = sp.getString(_debugKeyPref) ?? '';
    _loadModelsCache(sp);
    _loaded = true;
    return _config;
  }

  /// 保存配置。
  /// [touchDebugKey] 为 true 表示调用方**显式管理**调试 Key（可设可清）；为 false 时
  /// 若传入的配置没带调试 Key，就沿用内存里已有的——调试 Key 是设备级设置，
  /// 不该被每次「保存表单」冲掉（曾因此让「测试连接」报「请先填写 API Key」）。
  Future<void> save(AiConfig c, {bool touchDebugKey = false}) async {
    if (!touchDebugKey && c.debugApiKey.trim().isEmpty) {
      c.debugApiKey = _config.debugApiKey;
    }
    _config = c;
    _loaded = true;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_spKey, AiConfig.encode(c)); // 调试 Key 不参与持久化 JSON
    if (kDebugMode) {
      final k = c.debugApiKey.trim();
      if (k.isEmpty) {
        await sp.remove(_debugKeyPref);
      } else {
        await sp.setString(_debugKeyPref, k);
      }
    }
  }

  /// 识图是否可用（已开启、参数齐全，且「AI 设置」插件没被停用）。
  /// 插件停用后配置仍在，但调用方一律走「不可用」分支：验证码退回人工输入、
  /// 校历识别入口消失。插件只按 id 引用（不 import 插件文件），删掉插件也编译得过。
  bool get available => _config.ready && PluginRegistry.I.isEnabled(_aiPluginId);

  // ==================== 模型列表 ====================

  void _loadModelsCache(SharedPreferences sp) {
    final raw = sp.getString(_modelsCacheKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        j.forEach((k, v) {
          if (v is List) _modelsCache[k.toString()] = v.map((e) => e.toString()).toList();
        });
      }
    } catch (_) {}
  }

  /// 某提供商已缓存的模型列表（上次拉取成功的），没有则空。
  List<String> cachedModels(String providerId) => _modelsCache[providerId] ?? const [];

  Future<void> _saveModelsCache(String providerId, List<String> models) async {
    _modelsCache[providerId] = models;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_modelsCacheKey, jsonEncode(_modelsCache));
  }

  /// 用当前 Key 调 `GET {base}/models` 拉真实可用模型；失败抛 ApiError。
  /// index 的实现失败时会回退注册表内置列表，这里把回退交给调用方（便于给出错误提示）。
  Future<List<String>> listModels({AiConfig? cfg}) async {
    await load();
    final c = cfg ?? _config;
    if (c.effectiveApiKey.isEmpty) throw ApiError('请先填写 API Key');
    if (c.baseUrl.isEmpty) throw ApiError('请先填写 Base URL');
    final url = '${c.baseUrl.replaceAll(RegExp(r'/+$'), '')}/models';
    http.Response resp;
    try {
      resp = await http.get(Uri.parse(url), headers: {
        'Authorization': 'Bearer ${c.effectiveApiKey}',
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw ApiError('拉取模型列表失败：$e');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final detail = utf8.decode(resp.bodyBytes, allowMalformed: true);
      throw ApiError('拉取模型列表失败（HTTP ${resp.statusCode}）：'
          '${detail.length > 160 ? detail.substring(0, 160) : detail}');
    }
    final ids = <String>[];
    try {
      final j = jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
      final data = (j is Map) ? j['data'] : null;
      if (data is List) {
        for (final m in data) {
          final id = (m is Map) ? '${m['id'] ?? ''}'.trim() : '';
          if (id.isNotEmpty) ids.add(id);
        }
      }
    } catch (_) {}
    if (ids.isEmpty) throw ApiError('该提供商未返回可用模型（或返回格式不识别）');
    ids.sort();
    await _saveModelsCache(c.providerId, ids);
    return ids;
  }

  /// 当前可选的模型：拉取到的（缓存）∪ 注册表内置，去重排序。
  List<String> selectableModels() {
    final p = _config.provider;
    final all = <String>{...cachedModels(p.id), ...p.models};
    final list = all.where((m) => m.trim().isNotEmpty).toList()..sort();
    return list;
  }

  // ==================== 识图 ====================

  /// 让模型读图并返回文本。失败抛 ApiError（调用方决定是否降级）。
  /// [thinkingOff] 为 true 时显式关闭思考（验证码识别用：只要短答案，思考纯属浪费）。
  Future<String> describeImage(
    Uint8List image, {
    required String prompt,
    String? system,
    String mime = 'image/png',
    Duration timeout = const Duration(seconds: 60),
    int maxTokens = 1024,
    bool thinkingOff = false,
  }) async {
    await load();
    final c = _config;
    if (!c.ready) {
      throw ApiError('尚未配置识图模型：请在「我的 → AI 设置」填写 API Key 与模型');
    }
    final url = '${c.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
    final body = _payload(c, prompt, system, image, mime, maxTokens, thinkingOff);
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${c.effectiveApiKey}',
    };

    http.Response resp;
    try {
      resp = await http.post(Uri.parse(url), headers: headers, body: jsonEncode(body)).timeout(timeout);
    } catch (e) {
      throw ApiError('调用 AI 失败（${c.provider.label}）：$e');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final detail = utf8.decode(resp.bodyBytes, allowMalformed: true);
      throw ApiError('AI 返回 ${resp.statusCode}：${detail.length > 200 ? detail.substring(0, 200) : detail}');
    }
    final text = _extractText(_decode(resp.bodyBytes));
    if (text.trim().isEmpty) throw ApiError('AI 未返回内容（模型可能不支持识图）');
    return text.trim();
  }

  /// 「测试连接」：发一张极小的图问一句，确认 Key/模型/地址都通。
  Future<String> testConnection() async {
    await load();
    final probe = _config.copy()
      ..enabled = true
      ..setApiKey(_config.effectiveApiKey);
    final saved = _config;
    _config = probe;
    try {
      return await describeImage(
        _tinyPng,
        prompt: '请只回复两个字：成功',
        timeout: const Duration(seconds: 30),
        maxTokens: 256,
      );
    } finally {
      _config = saved;
    }
  }

  // ==================== 请求构造 ====================

  Map<String, dynamic> _payload(
    AiConfig c,
    String prompt,
    String? system,
    Uint8List image,
    String mime,
    int maxTokens,
    bool thinkingOff,
  ) {
    final b64 = base64Encode(image);
    final payload = <String, dynamic>{
      'model': c.model.trim(),
      'max_tokens': maxTokens,
      'stream': false,
      'messages': [
        if (system != null && system.isNotEmpty) {'role': 'system', 'content': system},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:$mime;base64,$b64'},
            },
          ],
        },
      ],
    };
    if (thinkingOff) _applyThinkingOff(payload, c.providerId, c.model.trim());
    return payload;
  }

  /// 关闭思考：照抄 index `aisettings.apply_thinking(level="off")` 的分厂商写法。
  /// 未识别的提供商不加参数（乱加会 400）。
  static void _applyThinkingOff(Map<String, dynamic> payload, String providerId, String model) {
    final pid = providerId.toLowerCase();
    switch (pid) {
      case 'deepseek':
        payload['thinking'] = {'type': 'disabled'};
      case 'kimi':
        if (model.startsWith('kimi-k3')) {
          payload['reasoning_effort'] = 'none';
        } else {
          payload['thinking'] = {'type': 'disabled'};
        }
      case 'qwen':
      case 'dashscope':
        payload['enable_thinking'] = false;
      case 'gpt':
      case 'openai':
      case 'gemini':
      case 'google':
      case 'mimo':
        payload['reasoning_effort'] = 'none';
      default:
        break; // opencode-go / glm / custom：格式不确定，不加
    }
  }

  dynamic _decode(Uint8List bytes) {
    try {
      return jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  /// 取模型输出文本（OpenAI 兼容格式；兼容分段数组）。
  String _extractText(dynamic j) {
    if (j is! Map) return '';
    final choices = j['choices'];
    if (choices is List && choices.isNotEmpty) {
      final msg = (choices.first as Map)['message'];
      if (msg is Map) {
        final content = msg['content'];
        if (content is String) return content;
        if (content is List) {
          final buf = StringBuffer();
          for (final part in content) {
            if (part is Map) buf.write(part['text'] ?? '');
          }
          return buf.toString();
        }
      }
    }
    return '';
  }

  void debugDump() {
    if (!kDebugMode) return;
    debugPrint('[AI] provider=${_config.providerId} model=${_config.model} '
        'base=${_config.baseUrl} key=${_config.apiKey.isEmpty ? '未填' : '已填'}');
  }

  /// 1×1 透明 PNG：用于「测试连接」探活（不耗流量、不需要真实图片）。
  static final Uint8List _tinyPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
}
