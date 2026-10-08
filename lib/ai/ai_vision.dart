import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_error.dart';
import 'ai_settings.dart';

/// AI 识图（多模态对话）：直连模式下 App 自己调用户的 AI 服务，
/// 用于自动识别登录验证码、识别校历图片里的调休安排。
///
/// 请求形状与 index 后端 `deps.py: ai_vision_text` 对齐：
/// - `openai` → POST {baseUrl}/chat/completions，Bearer 鉴权，content 里放 image_url(data:)
/// - `anthropic` → POST {baseUrl}/v1/messages，x-api-key 鉴权，content 里放 base64 image
class AiVision {
  AiVision._();
  static final AiVision I = AiVision._();

  static const _spKey = 'ai_config';

  AiConfig _config = AiConfig();
  bool _loaded = false;

  AiConfig get config => _config;

  Future<AiConfig> load() async {
    if (_loaded) return _config;
    final sp = await SharedPreferences.getInstance();
    _config = AiConfig.decode(sp.getString(_spKey));
    _loaded = true;
    return _config;
  }

  Future<void> save(AiConfig c) async {
    _config = c;
    _loaded = true;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_spKey, AiConfig.encode(c));
  }

  /// 识图是否可用（已开启且参数齐全）。
  bool get available => _config.ready;

  /// 让模型读图并返回文本。失败抛 ApiError（调用方决定是否降级）。
  Future<String> describeImage(
    Uint8List image, {
    required String prompt,
    String? system,
    String mime = 'image/png',
    Duration timeout = const Duration(seconds: 60),
    int maxTokens = 1024,
  }) async {
    await load();
    final c = _config;
    if (!c.ready) {
      throw ApiError('尚未配置识图模型：请在「我的 → AI 设置」填写 API Key 与模型');
    }
    final url = _endpoint(c);
    final body = _payload(c, prompt, system, image, mime, maxTokens);
    final headers = {
      'Content-Type': 'application/json',
      ..._authHeaders(c),
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
    final text = _extractText(c, _decode(resp.bodyBytes));
    if (text.trim().isEmpty) throw ApiError('AI 未返回内容（模型可能不支持识图）');
    return text.trim();
  }

  /// 「测试连接」：发一张极小的图问一句，确认 Key/模型/地址都通。
  Future<String> testConnection() async {
    await load();
    final c = _config;
    // 测试时即便总开关没开也放行（用户正在配置）
    final probe = c.copy()..enabled = true;
    if (probe.apiKey.trim().isEmpty) throw ApiError('请先填写 API Key');
    if (probe.model.trim().isEmpty) throw ApiError('请先选择或填写模型');
    if (probe.baseUrl.isEmpty) throw ApiError('请先填写 Base URL');
    final saved = _config;
    _config = probe;
    try {
      final out = await describeImage(
        _tinyPng,
        prompt: '请只回复两个字：成功',
        timeout: const Duration(seconds: 30),
        maxTokens: 256,
      );
      return out;
    } finally {
      _config = saved;
    }
  }

  // ==================== 请求构造 ====================

  String _endpoint(AiConfig c) {
    final base = c.baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (c.provider.api == 'anthropic') {
      // Anthropic 的 base 不含 /v1，路径固定 /v1/messages
      return base.endsWith('/v1') ? '$base/messages' : '$base/v1/messages';
    }
    return '$base/chat/completions';
  }

  Map<String, String> _authHeaders(AiConfig c) => c.provider.api == 'anthropic'
      ? {
          'x-api-key': c.apiKey.trim(),
          'anthropic-version': '2023-06-01',
        }
      : {'Authorization': 'Bearer ${c.apiKey.trim()}'};

  Map<String, dynamic> _payload(
    AiConfig c,
    String prompt,
    String? system,
    Uint8List image,
    String mime,
    int maxTokens,
  ) {
    final b64 = base64Encode(image);
    if (c.provider.api == 'anthropic') {
      return {
        'model': c.model.trim(),
        'max_tokens': maxTokens,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image',
                'source': {'type': 'base64', 'media_type': mime, 'data': b64},
              },
              {'type': 'text', 'text': prompt},
            ],
          }
        ],
        if (system != null && system.isNotEmpty) 'system': system,
      };
    }
    return {
      'model': c.model.trim(),
      'max_tokens': maxTokens,
      'stream': false,
      'messages': [
        if (system != null && system.isNotEmpty)
          {'role': 'system', 'content': system},
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
  }

  dynamic _decode(Uint8List bytes) {
    try {
      return jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  /// 取模型输出文本：OpenAI `/chat/completions` 与 Anthropic `/messages` 分别解析。
  String _extractText(AiConfig c, dynamic j) {
    if (j is! Map) return '';
    if (c.provider.api == 'anthropic') {
      final content = j['content'];
      if (content is List) {
        final buf = StringBuffer();
        for (final part in content) {
          if (part is Map && part['type'] == 'text') buf.write(part['text'] ?? '');
        }
        return buf.toString();
      }
      return '';
    }
    final choices = j['choices'];
    if (choices is List && choices.isNotEmpty) {
      final msg = (choices.first as Map)['message'];
      if (msg is Map) {
        final content = msg['content'];
        if (content is String) return content;
        // 有的兼容层返回分段数组
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
