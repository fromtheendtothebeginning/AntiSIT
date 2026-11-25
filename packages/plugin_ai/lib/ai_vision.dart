import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_core/campus_core.dart';

import 'ai_config.dart';
import 'ai_vision_parse.dart';
import 'ai_vision_request.dart';

/// 「AI 设置」插件的 id（见 lib/plugins/features/ai_plugin.dart）。
/// 这里用字面量而不是 import 那个文件：插件是可删的，基础设施不该依赖某个插件存在。
const String _aiPluginId = PluginIds.ai;

/// AI 识图 / 对话：直连模式下 App 直接调用户的 AI 服务，统一走 OpenAI 兼容接口。
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

  static final http.Client _defaultClient = http.Client();

  /// 发请求用的客户端：单测注入 MockClient 用（见 test/ai_vision_test.dart），生产走默认实现。
  @visibleForTesting
  static http.Client? clientOverride;

  static http.Client get _client => clientOverride ?? _defaultClient;

  AiConfig get config => _config;

  /// 读本机配置（含旧版本明文的一次性迁移）与模型列表缓存。
  Future<AiConfig> load() async {
    if (_loaded) return _config;
    final sp = await SharedPreferences.getInstance();
    final secure = SecureStore.I;
    // API Key 可直接计费，走加密存储；旧版本留在 SharedPreferences 的明文一次性迁入并删除。
    var raw = await secure.read(_spKey);
    if (raw == null || raw.isEmpty) {
      final legacy = sp.getString(_spKey);
      if (legacy != null && legacy.isNotEmpty) {
        await secure.write(_spKey, legacy);
        raw = legacy;
      }
    }
    await sp.remove(_spKey);
    _config = AiConfig.decode(raw);
    // 开发期临时 Key：只存本机安全存储、不进仓库，且仅 debug 构建读取。
    if (kDebugMode) {
      var debugKey = await secure.read(_debugKeyPref);
      if (debugKey == null || debugKey.isEmpty) {
        final legacy = sp.getString(_debugKeyPref);
        if (legacy != null && legacy.isNotEmpty) {
          await secure.write(_debugKeyPref, legacy);
          debugKey = legacy;
        }
      }
      await sp.remove(_debugKeyPref);
      _config.debugApiKey = debugKey ?? '';
    }
    _loadModelsCache(sp);
    _loaded = true;
    return _config;
  }

  /// 保存配置。
  /// [touchDebugKey] 为 false 且传入配置没带调试 Key 时沿用内存里的值——
  /// 调试 Key 是设备级设置，不该被每次「保存表单」冲掉。
  Future<void> save(AiConfig c, {bool touchDebugKey = false}) async {
    if (!touchDebugKey && c.debugApiKey.trim().isEmpty) {
      c.debugApiKey = _config.debugApiKey;
    }
    _config = c;
    _loaded = true;
    final sp = await SharedPreferences.getInstance();
    final secure = SecureStore.I;
    await secure.write(_spKey, AiConfig.encode(c)); // 调试 Key 不参与持久化 JSON
    await sp.remove(_spKey); // 清掉旧版本可能留下的明文配置
    if (kDebugMode) {
      final k = c.debugApiKey.trim();
      if (k.isEmpty) {
        await secure.remove(_debugKeyPref);
      } else {
        await secure.write(_debugKeyPref, k);
      }
      await sp.remove(_debugKeyPref);
    }
  }

  /// 识图是否可用（已开启、参数齐全，且「AI 设置」插件没被停用）。
  bool get available => _config.ready && PluginRegistry.I.isEnabled(_aiPluginId);

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
  Future<List<String>> listModels({AiConfig? cfg}) async {
    await load();
    final c = cfg ?? _config;
    if (c.effectiveApiKey.isEmpty) throw ApiError('请先填写 API Key');
    if (c.baseUrl.isEmpty) throw ApiError('请先填写 Base URL');
    final url = '${c.baseUrl.replaceAll(RegExp(r'/+$'), '')}/models';
    http.Response resp;
    try {
      resp = await _client.get(Uri.parse(url), headers: {
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

  /// 让模型读图并返回文本。失败抛 ApiError（调用方决定是否降级）。
  /// [thinkingOff] 为 true 时显式关闭思考；首次回答为空时自动关思考再试一次——
  /// 思考内容与正式回答共享 max_tokens，推理吃光预算就只剩空 content。
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
    if (!_config.ready) {
      throw ApiError('尚未配置识图模型：请在「我的 → AI 设置」填写 API Key 与模型');
    }
    var reply = await _chat(image,
        prompt: prompt,
        system: system,
        mime: mime,
        maxTokens: maxTokens,
        thinkingOff: thinkingOff,
        timeout: timeout);
    if (reply.text.isEmpty && !thinkingOff) {
      reply = await _chat(image,
          prompt: prompt,
          system: system,
          mime: mime,
          maxTokens: maxTokens,
          thinkingOff: true,
          timeout: timeout);
    }
    if (reply.text.isNotEmpty) return reply.text;
    // finish_reason=length 说明撞上了 max_tokens，与「模型不支持识图」是两回事。
    throw ApiError(reply.finishReason == 'length'
        ? 'AI 输出被截断（撞上 token 上限），没有给出结果：请重试或换一个模型'
        : 'AI 未返回内容（模型可能不支持识图）');
  }

  /// 发一次带图对话请求，返回 (输出文本, finish_reason)。
  Future<({String text, String finishReason})> _chat(
    Uint8List image, {
    required String prompt,
    String? system,
    required String mime,
    required int maxTokens,
    required bool thinkingOff,
    required Duration timeout,
  }) {
    return _sendChat(
        buildImagePayload(_config, prompt, system, image, mime, maxTokens,
            thinkingOff),
        timeout);
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

  /// 一轮纯文本对话：提示词进、回答文本出；首次回答为空自动关思考重试一次。
  Future<String> chat(
    String prompt, {
    String? system,
    int maxTokens = 1024,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    await load();
    if (!_config.ready) {
      throw ApiError('尚未配置 AI：请在「我的 → AI 设置」填写 API Key 与模型');
    }
    var reply = await _chatText(prompt,
        system: system, maxTokens: maxTokens, thinkingOff: false, timeout: timeout);
    if (reply.text.isEmpty) {
      reply = await _chatText(prompt,
          system: system, maxTokens: maxTokens, thinkingOff: true, timeout: timeout);
    }
    if (reply.text.isNotEmpty) return reply.text;
    throw ApiError(reply.finishReason == 'length'
        ? 'AI 输出被截断（撞上 token 上限），没有给出结果：请重试或换一个模型'
        : 'AI 未返回内容');
  }

  /// 文本对话的请求体：user content 直接是字符串。
  Future<({String text, String finishReason})> _chatText(
    String prompt, {
    String? system,
    required int maxTokens,
    required bool thinkingOff,
    required Duration timeout,
  }) {
    return _sendChat(
        buildTextPayload(_config, prompt, system, maxTokens, thinkingOff),
        timeout);
  }

  /// 发一次对话请求并解开回答。
  Future<({String text, String finishReason})> _sendChat(
    Map<String, dynamic> body,
    Duration timeout,
  ) async {
    final j = await postChatRequest(_client, _config, body, timeout);
    return (text: chatReplyText(j).trim(), finishReason: chatFinishReason(j));
  }

  /// 多轮对话；[tools] 非空时按 OpenAI 兼容的 function calling 发。
  /// 提供商不认 tools（400 / 422 且错误里提到 tool/function）时自动去掉 tools 重试。
  Future<AiChatReply> chatWithTools(
    List<AiChatMessage> messages, {
    List<AiToolSpec> tools = const [],
    int maxTokens = 2048,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    await load();
    if (!_config.ready) {
      throw ApiError('尚未配置 AI：请在「我的 → AI 设置」填写 API Key 与模型');
    }
    var useTools = tools.isNotEmpty;
    var reply = await _requestMessages(messages,
        tools: useTools ? tools : const [],
        maxTokens: maxTokens,
        thinkingOff: false,
        timeout: timeout,
        usedTools: useTools);
    if (useTools && reply.toolCalls.isEmpty && reply.text.isEmpty) {
      // 空回复常见于「思考把 max_tokens 吃光」；先关思考再试一次，别急着丢 tools。
      reply = await _requestMessages(messages,
          tools: tools,
          maxTokens: maxTokens,
          thinkingOff: true,
          timeout: timeout,
          usedTools: true);
    }
    if (reply.text.isEmpty && reply.toolCalls.isEmpty) {
      throw ApiError(reply.finishReason == 'length'
          ? 'AI 输出被截断（撞上 token 上限），没有给出结果：请重试或换一个模型'
          : 'AI 未返回内容');
    }
    return reply;
  }

  /// 流式版 [chatWithTools]：SSE 增量边收边回调，结束时返回完整回复。
  /// 端点忽略 `stream` 时把全文当一次增量回调；不支持 tools 时去掉 tools 重试。
  Future<AiChatReply> chatWithToolsStream(
    List<AiChatMessage> messages, {
    List<AiToolSpec> tools = const [],
    int maxTokens = 2048,
    Duration timeout = const Duration(seconds: 90),
    void Function(String delta)? onText,
    void Function(String delta)? onReasoning,
  }) async {
    await load();
    if (!_config.ready) {
      throw ApiError('尚未配置 AI：请在「我的 → AI 设置」填写 API Key 与模型');
    }
    try {
      return await _requestMessagesStream(messages,
          tools: tools,
          maxTokens: maxTokens,
          thinkingOff: false,
          timeout: timeout,
          usedTools: tools.isNotEmpty,
          onText: onText,
          onReasoning: onReasoning);
    } on ApiError catch (e) {
      if (!_looksLikeStreamUnsupported(e.message)) rethrow;
      // 有些兼容端点不认 stream：退回普通请求，全文一次回调。
      final reply = await chatWithTools(messages,
          tools: tools, maxTokens: maxTokens, timeout: timeout);
      if (reply.reasoning.isNotEmpty) onReasoning?.call(reply.reasoning);
      if (reply.text.isNotEmpty) onText?.call(reply.text);
      return reply;
    }
  }

  static bool _looksLikeStreamUnsupported(String message) {
    final m = message.toLowerCase();
    return (m.contains('400') || m.contains('422') || m.contains('invalid')) &&
        m.contains('stream');
  }

  Future<AiChatReply> _requestMessagesStream(
    List<AiChatMessage> messages, {
    required List<AiToolSpec> tools,
    required int maxTokens,
    required bool thinkingOff,
    required Duration timeout,
    required bool usedTools,
    void Function(String delta)? onText,
    void Function(String delta)? onReasoning,
  }) async {
    final body =
        buildMessagesPayload(_config, messages, tools, maxTokens, thinkingOff);
    body['stream'] = true;
    try {
      return await _sendStream(body, timeout,
          usedTools: usedTools, onText: onText, onReasoning: onReasoning);
    } on ApiError catch (e) {
      if (tools.isEmpty || !_looksLikeToolsUnsupported(e.message)) rethrow;
      final fallback =
          buildMessagesPayload(_config, messages, const [], maxTokens, thinkingOff);
      fallback['stream'] = true;
      return _sendStream(fallback, timeout,
          usedTools: false, onText: onText, onReasoning: onReasoning);
    }
  }

  /// 发起流式请求并把回复解出来。
  Future<AiChatReply> _sendStream(
    Map<String, dynamic> body,
    Duration timeout, {
    required bool usedTools,
    void Function(String delta)? onText,
    void Function(String delta)? onReasoning,
  }) {
    return sendChatStream(_client, _config, body, timeout,
        usedTools: usedTools, onText: onText, onReasoning: onReasoning);
  }

  Future<AiChatReply> _requestMessages(
    List<AiChatMessage> messages, {
    required List<AiToolSpec> tools,
    required int maxTokens,
    required bool thinkingOff,
    required Duration timeout,
    required bool usedTools,
  }) async {
    final body =
        buildMessagesPayload(_config, messages, tools, maxTokens, thinkingOff);
    try {
      return parseChatReply(
          await postChatRequest(_client, _config, body, timeout),
          usedTools: usedTools);
    } on ApiError catch (e) {
      if (tools.isEmpty || !_looksLikeToolsUnsupported(e.message)) rethrow;
      // 这家模型 / 端点不支持 function calling：去掉 tools 再来一次。
      final fallback =
          buildMessagesPayload(_config, messages, const [], maxTokens, thinkingOff);
      return parseChatReply(
          await postChatRequest(_client, _config, fallback, timeout),
          usedTools: false);
    }
  }

  static bool _looksLikeToolsUnsupported(String message) {
    final m = message.toLowerCase();
    return (m.contains('400') || m.contains('422') || m.contains('invalid')) &&
        (m.contains('tool') || m.contains('function') || m.contains('unsupported'));
  }

  /// 关闭思考的请求字段：写法随提供商插件走，实现见 [thinkingOffPayload]。
  static Map<String, dynamic> applyThinkingOff(String providerId, String model) =>
      thinkingOffPayload(providerId, model);

  /// 1×1 透明 PNG：用于「测试连接」探活（不耗流量、不需要真实图片）。
  static final Uint8List _tinyPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
}
