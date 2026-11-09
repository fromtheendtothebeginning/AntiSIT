import 'dart:typed_data';

import 'capability.dart';

/// 一条调休规则：与课表 store 的 `TtAdjust` 同形（date + type + day）。
/// 放在契约层：AI 能力（提供方 plugin_ai）与课表（消费方 plugin_timetable）都要用它。
class HolidayRule {
  const HolidayRule({required this.date, required this.type, this.day});

  final String date; // yyyy-MM-dd
  final String type; // off | follow
  final int? day; // follow 时 0-6（0=周一）

  Map<String, dynamic> toJson() => {
        'date': date,
        'type': type,
        if (day != null) 'day': day,
      };
}

/// 一条对话消息（OpenAI 兼容形状，供 Agent 循环使用）。
class AiChatMessage {
  const AiChatMessage({
    required this.role,
    this.content = '',
    this.toolCalls = const [],
    this.toolCallId = '',
  });

  final String role; // system / user / assistant / tool

  final String content;

  /// assistant 消息里的工具调用（原生 tool calling）。
  final List<AiToolCall> toolCalls;

  /// role=tool 时对应哪一次调用。
  final String toolCallId;

  factory AiChatMessage.system(String text) =>
      AiChatMessage(role: 'system', content: text);
  factory AiChatMessage.user(String text) =>
      AiChatMessage(role: 'user', content: text);
  factory AiChatMessage.assistant(String text, {List<AiToolCall> toolCalls = const []}) =>
      AiChatMessage(role: 'assistant', content: text, toolCalls: toolCalls);
  factory AiChatMessage.tool(String callId, String text) =>
      AiChatMessage(role: 'tool', content: text, toolCallId: callId);
}

/// 模型要求调用的一次工具。
class AiToolCall {
  const AiToolCall({required this.id, required this.name, required this.argumentsJson});

  final String id;
  final String name;

  /// 参数 JSON 原文（模型给的，不保证合法，执行前要解析校验）。
  final String argumentsJson;
}

/// 暴露给模型的一份工具 schema。
class AiToolSpec {
  const AiToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;

  /// JSON Schema（type=object + properties + required）。
  final Map<String, dynamic> parameters;
}

/// 一次模型回复：文本和/或工具调用。
class AiChatReply {
  const AiChatReply({
    this.text = '',
    this.reasoning = '',
    this.toolCalls = const [],
    this.finishReason = '',
    this.usedTools = false,
  });

  final String text;

  /// 思考型模型返回的推理过程（`reasoning_content` / `reasoning`）。
  /// 普通模型为空；工坊把它折叠展示，不混进正式回答。
  final String reasoning;

  final List<AiToolCall> toolCalls;
  final String finishReason;

  /// 本次请求是否真的带了 tools（false = 走的是纯文本降级）。
  final bool usedTools;
}

/// AI 识图能力（提供方：AI 设置插件 `PluginIds.ai`）。
///
/// 课表页（校历识别）与 core 的验证码弹窗（自动识码）都通过
/// `PluginRegistry.I.capability<AiCapability>(PluginIds.ai)` 取用，
/// 谁都不 import plugin_ai——实现留在那个包里。
abstract class AiCapability implements PluginCapability {
  /// 读一次本机配置；用到之前先 await 它，[available] 与摘要才准。
  Future<void> load();

  /// 已开启、参数齐全，且 AI 插件没被停用/删掉。
  bool get available;

  /// 当前选中的提供商（宿主插件管理页显示「当前「X」」用）。
  String get providerLabel;
  String get providerId;

  /// 验证码识别：识别成功返回文字，失败返回 null（调用方回退手动输入）。
  Future<String?> solveCaptcha(Uint8List image);

  /// 从校历图片里识别调休安排（日期按 [startDate] 起、[weekCount] 周的学期范围校验）。
  Future<List<HolidayRule>> parseHolidayImage(
    Uint8List image, {
    required String startDate,
    required int weekCount,
    String mime = 'image/png',
  });

  /// 纯文本对话：提示词进、回答文本出（拓展的 `ai.chat` 接口走这里）。
  /// 请求由 App 本地按当前提供商的协议构造（Key / 模型都不出 App），失败抛 ApiError。
  /// [maxTokens] 缺省由实现决定；没配置模型 / 插件被停用时先用 [available] 判断。
  Future<String> chat(String prompt, {String? system, int? maxTokens});

  /// 多轮对话 + 原生工具调用（拓展工坊的 Agent 循环走这里）。
  /// [tools] 为空就是普通多轮文本；提供商不支持 tools 时实现应尽量降级为空工具重试，
  /// 调用方也可以根据 [AiChatReply.usedTools] 判断是否要改走文本协议。
  Future<AiChatReply> chatWithTools(
    List<AiChatMessage> messages, {
    List<AiToolSpec> tools = const [],
    int? maxTokens,
  });

  /// 流式版 [chatWithTools]：边收边把增量交给 [onText] / [onReasoning]，
  /// 结束时仍返回完整回复（工具调用在流结束后一次性给出）。
  /// 提供商不支持流式时实现应退回普通请求，把完整文本作为一次增量回调。
  Future<AiChatReply> chatWithToolsStream(
    List<AiChatMessage> messages, {
    List<AiToolSpec> tools = const [],
    int? maxTokens,
    void Function(String delta)? onText,
    void Function(String delta)? onReasoning,
  });
}
