import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:campus_core/campus_core.dart';

import 'ai_config.dart';
import 'ai_vision_parse.dart';

/// 关闭思考要往请求体里加的字段：转发给这家提供商插件——写法随包走。
/// 没装这家 / 这家被停用 / 这家没写时返回空 Map（格式不确定时乱加会 400）。
Map<String, dynamic> thinkingOffPayload(String providerId, String model) {
  final r = PluginRegistry.I;
  if (!r.isProviderEnabled(providerId)) return const {};
  return r.providerById(providerId)!.thinkingOff(model);
}

/// 识图请求体：user content 里放 text + image_url(data:)。
Map<String, dynamic> buildImagePayload(
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
  if (thinkingOff) {
    payload.addAll(thinkingOffPayload(c.providerId, c.model.trim()));
  }
  return payload;
}

/// 文本对话的请求体：没有 image_url 那一段，user content 直接是字符串。
Map<String, dynamic> buildTextPayload(
  AiConfig c,
  String prompt,
  String? system,
  int maxTokens,
  bool thinkingOff,
) {
  return {
    'model': c.model.trim(),
    'max_tokens': maxTokens,
    'stream': false,
    'messages': [
      if (system != null && system.isNotEmpty) {'role': 'system', 'content': system},
      {'role': 'user', 'content': prompt},
    ],
    if (thinkingOff) ...thinkingOffPayload(c.providerId, c.model.trim()),
  };
}

/// 多轮对话请求体；tools 非空时按 OpenAI function calling 发。
Map<String, dynamic> buildMessagesPayload(
  AiConfig c,
  List<AiChatMessage> messages,
  List<AiToolSpec> tools,
  int maxTokens,
  bool thinkingOff,
) {
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
    if (thinkingOff) ...thinkingOffPayload(c.providerId, c.model.trim()),
  };
  return body;
}

/// 发一次对话请求并解出 JSON；失败时把提供商返回的前 200 字带进错误里。
Future<dynamic> postChatRequest(
  http.Client client,
  AiConfig c,
  Map<String, dynamic> body,
  Duration timeout,
) async {
  final url = '${c.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
  http.Response resp;
  try {
    resp = await client
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
  return decodeJsonBody(resp.bodyBytes);
}

/// 发起流式对话请求并解出回复；HTTP 错误在这里转成 ApiError。
Future<AiChatReply> sendChatStream(
  http.Client client,
  AiConfig c,
  Map<String, dynamic> body,
  Duration timeout, {
  required bool usedTools,
  void Function(String delta)? onText,
  void Function(String delta)? onReasoning,
}) async {
  final url = '${c.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
  http.StreamedResponse res;
  try {
    final req = http.Request('POST', Uri.parse(url))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Bearer ${c.effectiveApiKey}'
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode(body);
    res = await client.send(req).timeout(timeout);
  } catch (e) {
    throw ApiError('调用 AI 失败（${c.provider.label}）：$e');
  }
  if (res.statusCode < 200 || res.statusCode >= 300) {
    final bytes = await res.stream.toBytes().timeout(timeout);
    final detail = utf8.decode(bytes, allowMalformed: true);
    throw ApiError(
        'AI 返回 ${res.statusCode}：${detail.length > 200 ? detail.substring(0, 200) : detail}');
  }
  return parseChatStream(
    res,
    providerLabel: c.provider.label,
    usedTools: usedTools,
    timeout: timeout,
    onText: onText,
    onReasoning: onReasoning,
  );
}
