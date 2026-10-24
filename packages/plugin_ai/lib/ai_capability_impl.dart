import 'dart:typed_data';

import 'package:campus_core/campus_core.dart';

import 'ai_tasks.dart' as tasks;
import 'ai_vision.dart';

/// AI 能力的实现：把本包内的 [AiVision] / 识图任务暴露给别的插件与 core 用
/// （课表页识别校历、core 的验证码弹窗自动识码）。
///
/// 声明在 `pluginBundle.capabilities` 里（key = 本插件 id）；消费方只能拿到
/// campus_core 里的 [AiCapability] 接口，看不到这个类，也不 import 本包。
/// 本插件被停用时注册表查不到它，消费方自然降级（验证码退回手输、校历入口消失）。
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
}
