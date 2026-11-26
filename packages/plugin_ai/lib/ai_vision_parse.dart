import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:campus_core/campus_core.dart';

/// 一条流式 tool call 的累积器（按 index 收 id / name / arguments 碎片）。
class _StreamToolCall {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}

/// 解出响应体 JSON；解不开返回 null。
dynamic decodeJsonBody(Uint8List bytes) {
  try {
    return jsonDecode(utf8.decode(bytes, allowMalformed: true));
  } catch (_) {
    return null;
  }
}

/// 取 content 文本（OpenAI 兼容格式；兼容分段数组）。
String chatContentText(dynamic content) {
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

/// 取模型输出文本。
String chatReplyText(dynamic j) {
  if (j is! Map) return '';
  final choices = j['choices'];
  if (choices is List && choices.isNotEmpty) {
    final msg = (choices.first as Map)['message'];
    if (msg is Map) {
      return chatContentText(msg['content']);
    }
  }
  return '';
}

/// 取思考型模型的推理过程（各家字段名略有差异）。
String chatReplyReasoning(dynamic j) {
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

/// 模型输出的结束原因（'length' = 撞到 max_tokens 被截断）。
String chatFinishReason(dynamic j) {
  if (j is! Map) return '';
  final choices = j['choices'];
  if (choices is List && choices.isNotEmpty && choices.first is Map) {
    return '${(choices.first as Map)['finish_reason'] ?? ''}';
  }
  return '';
}

/// 解析非流式回复（含 function calling 的 tool_calls）。
AiChatReply parseChatReply(dynamic j, {required bool usedTools}) {
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
    text: chatReplyText(j).trim(),
    reasoning: chatReplyReasoning(j),
    toolCalls: toolCalls,
    finishReason: chatFinishReason(j),
    usedTools: usedTools,
  );
}

/// 解析流式响应：SSE 增量边收边回调；端点忽略 stream 时把整份 JSON 当一次增量。
Future<AiChatReply> parseChatStream(
  http.StreamedResponse res, {
  required String providerLabel,
  required bool usedTools,
  required Duration timeout,
  void Function(String delta)? onText,
  void Function(String delta)? onReasoning,
}) async {
  // 端点忽略了 stream：响应是一整份 JSON，把完整回答当成一次增量。
  final contentType = (res.headers['content-type'] ?? '').toLowerCase();
  if (!contentType.contains('event-stream')) {
    final reply = parseChatReply(
        decodeJsonBody(await res.stream.toBytes().timeout(timeout)),
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
      final piece = chatContentText(delta['content']);
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
    throw ApiError('读取 AI 流式输出失败（$providerLabel）：$e');
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
