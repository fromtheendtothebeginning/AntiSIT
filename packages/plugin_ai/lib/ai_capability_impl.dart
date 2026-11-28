import 'dart:typed_data';

import 'package:campus_core/campus_core.dart';

import 'ai_tasks.dart' as tasks;
import 'ai_vision.dart';

/// AI 能力的实现：把 [AiVision] 与识图任务暴露给别的插件与 core 用。
/// 声明在 `pluginBundle.capabilities` 里（key = 本插件 id），消费方只看到 [AiCapability]。
class AiCapabilityImpl implements AiCapability {
  const AiCapabilityImpl();

  @override
  Future<void> load() => AiVision.I.load();

  @override
  bool get available => AiVision.I.available;

  @override
  String get providerLabel => AiVision.I.config.provider.label;

  @override
  String get providerId => AiVision.I.config.providerId;

  @override
  String get currentModel => AiVision.I.config.model.trim();

  @override
  List<String> get selectableModels => AiVision.I.selectableModels();

  @override
  Future<void> setModel(String model) => AiVision.I.setModel(model);

  @override
  Future<String?> solveCaptcha(Uint8List image) => tasks.solveCaptcha(image);

  @override
  Future<List<HolidayRule>> parseHolidayImage(
    Uint8List image, {
    required String startDate,
    required int weekCount,
    String mime = 'image/png',
  }) =>
      tasks.parseHolidayImage(image, startDate: startDate, weekCount: weekCount, mime: mime);

  @override
  Future<String> chat(String prompt, {String? system, int? maxTokens}) =>
      AiVision.I.chat(prompt, system: system, maxTokens: maxTokens ?? 1024);

  @override
  Future<AiChatReply> chatWithTools(
    List<AiChatMessage> messages, {
    List<AiToolSpec> tools = const [],
    int? maxTokens,
  }) =>
      AiVision.I.chatWithTools(messages,
          tools: tools, maxTokens: maxTokens ?? 2048);

  @override
  Future<AiChatReply> chatWithToolsStream(
    List<AiChatMessage> messages, {
    List<AiToolSpec> tools = const [],
    int? maxTokens,
    String reasoningEffort = '',
    void Function(String delta)? onText,
    void Function(String delta)? onReasoning,
  }) =>
      AiVision.I.chatWithToolsStream(messages,
          tools: tools,
          maxTokens: maxTokens ?? 2048,
          reasoningEffort: reasoningEffort,
          onText: onText,
          onReasoning: onReasoning);
}
