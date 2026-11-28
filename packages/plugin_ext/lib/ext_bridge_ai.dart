import 'dart:async';
import 'dart:convert';

import 'package:campus_core/campus_core.dart';

/// AI 对话通道：`ai.*` 的参数解析与调用。
///
/// 提示词由 App 本地转成当前 AI 提供商的请求（Key / 模型都留在 App 侧，
/// 网页只拿到回答文本）；AI 插件没装 / 被停用 / 没配置都如实报错。
class ExtAiChannel {
  ExtAiChannel({required this.events});

  /// 内核 → 网页的下行通道（流式增量用）；页面关掉后返回 null。
  final WebBridgeEventSink? Function() events;

  static const int _maxAiTextChars = 32768;

  Future<Object?> chat(Object? args) async {
    if (args is! Map) throw ArgumentError('ai.chat 要带 {prompt}');
    final prompt = '${args['prompt'] ?? ''}'.trim();
    if (prompt.isEmpty) throw ArgumentError('prompt 不能为空');
    if (prompt.length > _maxAiTextChars) {
      throw ArgumentError('prompt 太长（最多 $_maxAiTextChars 字）');
    }
    final system = args['system']?.toString();
    if (system != null && system.length > _maxAiTextChars) {
      throw ArgumentError('system 太长（最多 $_maxAiTextChars 字）');
    }
    final maxRaw = args['maxTokens'];
    final int maxTokens;
    if (maxRaw == null) {
      maxTokens = 1024;
    } else if (maxRaw is num && maxRaw > 0) {
      maxTokens = maxRaw.toInt().clamp(16, 4096).toInt();
    } else {
      throw ArgumentError('maxTokens 要是正数（缺省 1024，收在 16–4096）');
    }
    final ai = _requireAi();
    return ai.chat(prompt, system: system, maxTokens: maxTokens);
  }

  Future<Object?> chatTools(Object? args) async {
    final parsed = _parseAiRequest(args, methodName: 'ai.chatTools');
    final ai = _requireAi();
    final reply = await ai.chatWithTools(
      parsed.messages,
      tools: parsed.tools,
      maxTokens: parsed.maxTokens,
    );
    return _aiReplyJson(reply);
  }

  /// 流式多轮对话：增量推给网页的 `antiSIT.on('ai.stream')`，返回值仍是完整回复。
  /// `streamId` 由网页生成并随事件带回，网页可以只认自己那一轮。
  Future<Object?> chatToolsStream(Object? args) async {
    final a = args is Map ? args : const {};
    final streamId = '${a['streamId'] ?? ''}'.trim();
    if (streamId.isEmpty) {
      throw ArgumentError('ai.chatToolsStream 要带 {streamId}');
    }
    final parsed = _parseAiRequest(args, methodName: 'ai.chatToolsStream');
    final ai = _requireAi();
    // 模型是 token 级增量，每个 chunk 都 runJavaScript 会把 WebView 打满：
    // 攒 ~60ms 再推一次，最后在 finally 里把余量冲干净。
    final text = StringBuffer();
    final reasoning = StringBuffer();
    Timer? timer;
    void flush() {
      final sink = events();
      if (sink == null) {
        text.clear();
        reasoning.clear();
        return;
      }
      if (reasoning.isNotEmpty) {
        sink.emit('ai.stream', {
          'streamId': streamId,
          'kind': 'reasoning',
          'delta': reasoning.toString(),
        });
        reasoning.clear();
      }
      if (text.isNotEmpty) {
        sink.emit('ai.stream', {
          'streamId': streamId,
          'kind': 'text',
          'delta': text.toString(),
        });
        text.clear();
      }
    }

    void schedule() {
      timer ??= Timer(const Duration(milliseconds: 60), () {
        timer = null;
        flush();
      });
    }

    try {
      final reply = await ai.chatWithToolsStream(
        parsed.messages,
        tools: parsed.tools,
        maxTokens: parsed.maxTokens,
        reasoningEffort: parsed.reasoningEffort,
        onText: (delta) {
          text.write(delta);
          schedule();
        },
        onReasoning: (delta) {
          reasoning.write(delta);
          schedule();
        },
      );
      return _aiReplyJson(reply);
    } finally {
      timer?.cancel();
      flush();
    }
  }

  static ({
    List<AiChatMessage> messages,
    List<AiToolSpec> tools,
    int maxTokens,
    String reasoningEffort,
  })
  _parseAiRequest(Object? args, {required String methodName}) {
    if (args is! Map) throw ArgumentError('$methodName 要带 {messages}');
    final rawMessages = args['messages'];
    if (rawMessages is! List || rawMessages.isEmpty) {
      throw ArgumentError('messages 不能为空');
    }
    final messages = <AiChatMessage>[];
    for (final raw in rawMessages) {
      if (raw is! Map) continue;
      final role = '${raw['role'] ?? ''}'.trim();
      if (role.isEmpty) continue;
      final calls = <AiToolCall>[];
      final rawCalls = raw['toolCalls'] ?? raw['tool_calls'];
      if (rawCalls is List) {
        for (final c in rawCalls) {
          if (c is! Map) continue;
          final name =
              '${c['name'] ?? (c['function'] is Map ? (c['function'] as Map)['name'] : '') ?? ''}'
                  .trim();
          if (name.isEmpty) continue;
          final rawArgs =
              c['arguments'] ??
              (c['function'] is Map
                  ? (c['function'] as Map)['arguments']
                  : null) ??
              '{}';
          calls.add(
            AiToolCall(
              id: '${c['id'] ?? ''}'.trim(),
              name: name,
              argumentsJson: rawArgs is String ? rawArgs : jsonEncode(rawArgs),
            ),
          );
        }
      }
      messages.add(
        AiChatMessage(
          role: role,
          content: '${raw['content'] ?? ''}',
          toolCalls: calls,
          toolCallId: '${raw['toolCallId'] ?? raw['tool_call_id'] ?? ''}',
        ),
      );
    }
    if (messages.isEmpty) throw ArgumentError('messages 里没有有效消息');
    final tools = <AiToolSpec>[];
    final rawTools = args['tools'];
    if (rawTools is List) {
      for (final raw in rawTools) {
        if (raw is! Map) continue;
        final fn = raw['function'] is Map ? raw['function'] as Map : raw;
        final name = '${fn['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        tools.add(
          AiToolSpec(
            name: name,
            description: '${fn['description'] ?? ''}',
            parameters: fn['parameters'] is Map
                ? Map<String, dynamic>.from(fn['parameters'] as Map)
                : const {'type': 'object', 'properties': {}},
          ),
        );
      }
    }
    final rawMax = args['maxTokens'];
    final maxTokens = rawMax is num
        ? rawMax.toInt().clamp(256, 4096).toInt()
        : 4096;
    // 思考深度：只认固定几档，别让网页随便塞字符串进请求体。
    final effort = '${args['reasoningEffort'] ?? ''}'.trim().toLowerCase();
    final reasoningEffort =
        const {'', 'none', 'low', 'medium', 'high'}.contains(effort)
        ? effort
        : '';
    return (
      messages: messages,
      tools: tools,
      maxTokens: maxTokens,
      reasoningEffort: reasoningEffort,
    );
  }


  /// 当前可选的模型：内置清单 ∪ 上次从 `GET /models` 拉到的那份（去重排序）。
  Future<Object?> models(Object? args) async {
    final ai = _requireAi();
    return {
      'current': ai.currentModel,
      'models': ai.selectableModels,
    };
  }

  /// 当前提供商与模型（工坊顶栏显示「哪家 · 哪个」）。
  Future<Object?> current(Object? args) async {
    final ai = _requireAi();
    return {
      'provider': ai.providerLabel,
      'providerId': ai.providerId,
      'model': ai.currentModel,
    };
  }

  /// 切模型：只改 App 侧 AI 配置里的 model，下一次请求就生效。
  Future<Object?> setModel(Object? args) async {
    if (args is! Map) throw ArgumentError('ai.setModel 要带 {model}');
    final model = '${args['model'] ?? ''}'.trim();
    if (model.isEmpty) throw ArgumentError('model 不能为空');
    final ai = _requireAi();
    await ai.setModel(model);
    return {'model': ai.currentModel};
  }

  static AiCapability _requireAi() {
    final ai = PluginRegistry.I.capability<AiCapability>(PluginIds.ai);
    if (ai == null || !ai.available) {
      throw ArgumentError('AI 还没配好：到「我的 → AI 设置」选择提供商并填写 Key 与模型');
    }
    return ai;
  }

  static Map<String, Object?> _aiReplyJson(AiChatReply reply) => {
    'text': reply.text,
    'reasoning': reply.reasoning,
    'usedTools': reply.usedTools,
    'finishReason': reply.finishReason,
    'toolCalls': [
      for (final c in reply.toolCalls)
        {'id': c.id, 'name': c.name, 'arguments': c.argumentsJson},
    ],
  };
}
