import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_core/campus_core.dart';

import 'ai_config.dart';

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

  static final http.Client _defaultClient = http.Client();

  /// 发请求用的客户端：单测注入 MockClient 用（见 test/ai_vision_test.dart），生产走默认实现。
  @visibleForTesting
  static http.Client? clientOverride;

  static http.Client get _client => clientOverride ?? _defaultClient;

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

  // ==================== 识图 ====================

  /// 让模型读图并返回文本。失败抛 ApiError（调用方决定是否降级）。
  /// [thinkingOff] 为 true 时显式关闭思考（验证码识别用：只要短答案，思考纯属浪费）。
  ///
  /// 首次回答为空时自动**关掉思考再试一次**：思考型模型（官网：deepseek-flash
  /// 「thinking 默认开启，默认档位 high」）的推理内容与正式回答共享 max_tokens，
  /// 推理吃光预算就只剩空 content（finish_reason=length），报错文案还容易误导成
  /// 「模型不支持识图」。重试一次代价很小，却让默认配置直接可用。
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
    // finish_reason=length 说明撞上了 max_tokens（思考型模型还可能全被推理吃掉），
    // 这和「模型不支持识图」是两回事，别让用户去换错东西。
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
    return _sendChat(_payload(_config, prompt, system, image, mime, maxTokens, thinkingOff), timeout);
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

  // ==================== 纯文本对话 ====================

  /// 一轮纯文本对话：提示词进、回答文本出（拓展的 `ai.chat` 接口走这里）。
  /// 与识图同一条请求路径（OpenAI 兼容 /chat/completions，本地按当前提供商
  /// 拼 Key / 模型 / 关思考参数，见 [_chatText]）；首次回答为空自动关思考重试
  /// 一次——思考型模型把 max_tokens 全吃光的场景与识图相同（见 [describeImage]）。
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

  /// 文本对话的请求体：没有 image_url 那一段，user content 直接是字符串。
  Future<({String text, String finishReason})> _chatText(
    String prompt, {
    String? system,
    required int maxTokens,
    required bool thinkingOff,
    required Duration timeout,
  }) {
    final c = _config;
    return _sendChat({
      'model': c.model.trim(),
      'max_tokens': maxTokens,
      'stream': false,
      'messages': [
        if (system != null && system.isNotEmpty) {'role': 'system', 'content': system},
        {'role': 'user', 'content': prompt},
      ],
      if (thinkingOff) ...applyThinkingOff(c.providerId, c.model.trim()),
    }, timeout);
  }

  /// 发一次对话请求并解开回答：URL / 鉴权 / 状态码 / 超时的处理识图与文本对话共用。
  Future<({String text, String finishReason})> _sendChat(
    Map<String, dynamic> body,
    Duration timeout,
  ) async {
    final j = await _postChat(body, timeout);
    return (text: _extractText(j).trim(), finishReason: _finishReason(j));
  }

  /// 真正发请求并解出 JSON；失败时把提供商返回的前 200 字带进错误里。
  Future<dynamic> _postChat(Map<String, dynamic> body, Duration timeout) async {
    final c = _config;
    final url = '${c.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
    http.Response resp;
    try {
      resp = await _client
          .post(Uri.parse(url),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${c.effectiveApiKey}',
              },
              body: jsonEncode(body))
          .timeout(timeout);
    } catch (e) {
      throw ApiError('调用 AI 失败（${c.provider.label}）：$e');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final detail = utf8.decode(resp.bodyBytes, allowMalformed: true);
      throw ApiError(
          'AI 返回 ${resp.statusCode}：${detail.length > 200 ? detail.substring(0, 200) : detail}');
    }
    return _decode(resp.bodyBytes);
  }

  // ==================== 多轮对话 + 工具调用 ====================

  /// 多轮对话；[tools] 非空时按 OpenAI 兼容的 function calling 发。
  /// 提供商不认 tools（400 / 422 且错误里提到 tool/function）时自动去掉 tools 重试，
  /// 返回的 [AiChatReply.usedTools] 为 false，调用方可据此改走文本协议。
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
  ///
  /// 端点忽略 `stream`（回整份 JSON）时把全文当一次增量回调；不支持 tools
  /// （400 / 422 且错误里提到 tool/function）时去掉 tools 重试，与普通版一致。
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
    final body = _messagesPayload(messages, tools, maxTokens, thinkingOff);
    body['stream'] = true;
    try {
      return await _sendStream(body, timeout,
          usedTools: usedTools, onText: onText, onReasoning: onReasoning);
    } on ApiError catch (e) {
      if (tools.isEmpty || !_looksLikeToolsUnsupported(e.message)) rethrow;
      final fallback = _messagesPayload(messages, const [], maxTokens, thinkingOff);
      fallback['stream'] = true;
      return _sendStream(fallback, timeout,
          usedTools: false, onText: onText, onReasoning: onReasoning);
    }
  }

  Future<AiChatReply> _sendStream(
    Map<String, dynamic> body,
    Duration timeout, {
    required bool usedTools,
    void Function(String delta)? onText,
    void Function(String delta)? onReasoning,
  }) async {
    final c = _config;
    final url = '${c.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
    http.StreamedResponse res;
    try {
      final req = http.Request('POST', Uri.parse(url))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${c.effectiveApiKey}'
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode(body);
      res = await _client.send(req).timeout(timeout);
    } catch (e) {
      throw ApiError('调用 AI 失败（${c.provider.label}）：$e');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final bytes = await res.stream.toBytes().timeout(timeout);
      final detail = utf8.decode(bytes, allowMalformed: true);
      throw ApiError(
          'AI 返回 ${res.statusCode}：${detail.length > 200 ? detail.substring(0, 200) : detail}');
    }

    // 端点忽略了 stream：响应是一整份 JSON，把完整回答当成一次增量。
    final contentType = (res.headers['content-type'] ?? '').toLowerCase();
    if (!contentType.contains('event-stream')) {
      final reply = _parseReply(
          _decode(await res.stream.toBytes().timeout(timeout)),
          usedTools: usedTools);
      if (reply.reasoning.isNotEmpty) onReasoning?.call(reply.reasoning);
      if (reply.text.isNotEmpty) onText?.call(reply.text);
      return reply;
    }

    final text = StringBuffer();
    final reasoning = StringBuffer();
    final calls = <int, _StreamToolCall>{};
    var finishReason = '';
    try {
      final lines = res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(timeout);
      await for (final line in lines) {
        final raw = line.trim();
        if (raw.isEmpty || raw.startsWith(':') || !raw.startsWith('data:')) {
          continue;
        }
        final data = raw.substring(5).trim();
        if (data == '[DONE]') break;
        dynamic json;
        try {
          json = jsonDecode(data);
        } catch (_) {
          continue;
        }
        if (json is! Map) continue;
        final choices = json['choices'];
        if (choices is! List || choices.isEmpty || choices.first is! Map) {
          continue;
        }
        final choice = choices.first as Map;
        final delta = choice['delta'] is Map
            ? choice['delta'] as Map
            : choice['message'] is Map
                ? choice['message'] as Map
                : const {};
        final piece = _contentText(delta['content']);
        if (piece.isNotEmpty) {
          text.write(piece);
          onText?.call(piece);
        }
        final reason =
            delta['reasoning_content'] ?? delta['reasoning'] ?? delta['thinking'];
        if (reason is String && reason.isNotEmpty) {
          reasoning.write(reason);
          onReasoning?.call(reason);
        }
        final rawCalls = delta['tool_calls'];
        if (rawCalls is List) {
          for (final rawCall in rawCalls) {
            if (rawCall is! Map) continue;
            final index = rawCall['index'] is num
                ? (rawCall['index'] as num).toInt()
                : calls.length;
            final builder = calls.putIfAbsent(index, () => _StreamToolCall());
            final id = rawCall['id'];
            if (id is String && id.isNotEmpty) builder.id = id;
            final fn = rawCall['function'];
            if (fn is Map) {
              final name = fn['name'];
              if (name is String && name.isNotEmpty && builder.name.isEmpty) {
                builder.name = name;
              }
              final args = fn['arguments'];
              if (args is String && args.isNotEmpty) builder.arguments.write(args);
            }
          }
        }
        final fr = choice['finish_reason'];
        if (fr is String && fr.isNotEmpty) finishReason = fr;
      }
    } catch (e) {
      if (e is ApiError) rethrow;
      throw ApiError('读取 AI 流式输出失败（${c.provider.label}）：$e');
    }

    final toolCalls = <AiToolCall>[];
    final keys = calls.keys.toList()..sort();
    var n = 0;
    for (final key in keys) {
      final builder = calls[key]!;
      if (builder.name.isEmpty) continue;
      toolCalls.add(AiToolCall(
        id: builder.id.isEmpty
            ? 'call_${DateTime.now().microsecondsSinceEpoch}_${n++}'
            : builder.id,
        name: builder.name,
        argumentsJson:
            builder.arguments.isEmpty ? '{}' : builder.arguments.toString(),
      ));
    }
    final finalText = text.toString().trim();
    final finalReasoning = reasoning.toString().trim();
    if (finalText.isEmpty && toolCalls.isEmpty) {
      throw ApiError(finishReason == 'length'
          ? 'AI 输出被截断（撞上 token 上限），没有给出结果：请重试或换一个模型'
          : 'AI 未返回内容');
    }
    return AiChatReply(
      text: finalText,
      reasoning: finalReasoning,
      toolCalls: toolCalls,
      finishReason: finishReason,
      usedTools: usedTools,
    );
  }

  static String _contentText(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      final buf = StringBuffer();
      for (final part in content) {
        if (part is Map) buf.write(part['text'] ?? '');
      }
      return buf.toString();
    }
    return '';
  }

  Future<AiChatReply> _requestMessages(
    List<AiChatMessage> messages, {
    required List<AiToolSpec> tools,
    required int maxTokens,
    required bool thinkingOff,
    required Duration timeout,
    required bool usedTools,
  }) async {
    final body = _messagesPayload(messages, tools, maxTokens, thinkingOff);
    try {
      return _parseReply(await _postChat(body, timeout), usedTools: usedTools);
    } on ApiError catch (e) {
      if (tools.isEmpty || !_looksLikeToolsUnsupported(e.message)) rethrow;
      // 这家模型 / 端点不支持 function calling：去掉 tools 再来一次。
      final fallback = _messagesPayload(messages, const [], maxTokens, thinkingOff);
      return _parseReply(await _postChat(fallback, timeout), usedTools: false);
    }
  }

  static bool _looksLikeToolsUnsupported(String message) {
    final m = message.toLowerCase();
    return (m.contains('400') || m.contains('422') || m.contains('invalid')) &&
        (m.contains('tool') || m.contains('function') || m.contains('unsupported'));
  }

  Map<String, dynamic> _messagesPayload(
    List<AiChatMessage> messages,
    List<AiToolSpec> tools,
    int maxTokens,
    bool thinkingOff,
  ) {
    final c = _config;
    final body = <String, dynamic>{
      'model': c.model.trim(),
      'max_tokens': maxTokens,
      'stream': false,
      'messages': [
        for (final m in messages)
          {
            'role': m.role,
            'content': m.content,
            if (m.toolCalls.isNotEmpty)
              'tool_calls': [
                for (final call in m.toolCalls)
                  {
                    'id': call.id,
                    'type': 'function',
                    'function': {
                      'name': call.name,
                      'arguments': call.argumentsJson,
                    },
                  },
              ],
            if (m.toolCallId.isNotEmpty) 'tool_call_id': m.toolCallId,
          },
      ],
      if (tools.isNotEmpty) ...{
        'tools': [
          for (final t in tools)
            {
              'type': 'function',
              'function': {
                'name': t.name,
                'description': t.description,
                'parameters': t.parameters,
              },
            },
        ],
        'tool_choice': 'auto',
      },
      if (thinkingOff) ...applyThinkingOff(c.providerId, c.model.trim()),
    };
    return body;
  }

  AiChatReply _parseReply(dynamic j, {required bool usedTools}) {
    final toolCalls = <AiToolCall>[];
    if (j is Map) {
      final choices = j['choices'];
      if (choices is List && choices.isNotEmpty && choices.first is Map) {
        final msg = (choices.first as Map)['message'];
        if (msg is Map && msg['tool_calls'] is List) {
          for (final raw in msg['tool_calls'] as List) {
            if (raw is! Map) continue;
            final fn = raw['function'];
            if (fn is! Map) continue;
            final name = '${fn['name'] ?? ''}'.trim();
            if (name.isEmpty) continue;
            final args = fn['arguments'];
            toolCalls.add(AiToolCall(
              id: '${raw['id'] ?? ''}'.trim(),
              name: name,
              argumentsJson: args is String ? args : jsonEncode(args ?? const {}),
            ));
          }
        }
      }
    }
    return AiChatReply(
      text: _extractText(j).trim(),
      reasoning: _extractReasoning(j),
      toolCalls: toolCalls,
      finishReason: _finishReason(j),
      usedTools: usedTools,
    );
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
    if (thinkingOff) payload.addAll(applyThinkingOff(c.providerId, c.model.trim()));
    return payload;
  }

  /// 关闭思考要往请求体里加的字段：转发给这家提供商插件——**写法随包走**，
  /// 各家协议、出处与实测结论都写在各自包里的注释上（不再集中在 core 里 if/switch）。
  /// 没装这家 / 这家被停用 / 这家没写（opencode-go、glm、自定义）→ 空 Map = 不加字段：
  /// 格式不确定时乱加会 400，而停用的那家本来也不该参与请求。
  static Map<String, dynamic> applyThinkingOff(String providerId, String model) {
    final r = PluginRegistry.I;
    if (!r.isProviderEnabled(providerId)) return const {};
    return r.providerById(providerId)!.thinkingOff(model);
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
        return _contentText(msg['content']);
      }
    }
    return '';
  }

  /// 取思考型模型的推理过程（各家字段名略有差异）。
  String _extractReasoning(dynamic j) {
    if (j is! Map) return '';
    final choices = j['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final msg = (choices.first as Map)['message'];
      if (msg is Map) {
        final r = msg['reasoning_content'] ?? msg['reasoning'] ?? msg['thinking'];
        return r is String ? r.trim() : '';
      }
    }
    return '';
  }

  /// 模型输出的结束原因（'length' = 撞到 max_tokens 被截断，content 可能只有半截或为空）。
  String _finishReason(dynamic j) {
    if (j is! Map) return '';
    final choices = j['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      return '${(choices.first as Map)['finish_reason'] ?? ''}';
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

/// 一条流式 tool call 的累积器（按 index 收 id / name / arguments 碎片）。
class _StreamToolCall {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}
