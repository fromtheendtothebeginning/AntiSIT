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
}
