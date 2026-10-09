import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ai_vision.dart';

/// 验证码自动识别：识别成功返回文字，失败返回 null（调用方回退到手动输入框）。
/// 提示词与 index 后端 `campus_service._ai_solve_captcha` 一致。
Future<String?> solveCaptcha(Uint8List image) async {
  if (!AiVision.I.available) return null;
  try {
    final text = await AiVision.I.describeImage(
      image,
      prompt: '请只输出图片中的验证码字符本身（区分大小写；不要空格、标点、引号，也不要任何解释或说明）。',
      timeout: const Duration(seconds: 30),
      // 验证码只要几个字符：显式关掉思考，省时间也省 token
      // （思考型模型默认会先生成一大段推理，既慢又可能把 max_tokens 吃光）
      thinkingOff: true,
      maxTokens: 512,
    );
    final cleaned = text.replaceAll(RegExp(r'^["\s]+|["\s]+$'), '');
    return cleaned.isEmpty ? null : cleaned;
  } catch (e) {
    debugPrint('[AI] 验证码识别失败，回退手动输入：$e');
    return null;
  }
}

/// 一条调休规则：与课表 store 的 TtAdjust 同形（date + type + day）。
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

/// 系统提示词（与 index 后端 timetable_holiday.PARSE_SYSTEM 同义）。
const _holidaySystem = '你是校历解析助手。只输出 JSON，不要任何解释、前后缀或代码块标记。';

/// 从校历图片识别调休安排。日期按 [startDate]（第一周周一）与 [weekCount] 限定的学期范围校验。
Future<List<HolidayRule>> parseHolidayImage(
  Uint8List image, {
  required String startDate,
  required int weekCount,
  String mime = 'image/png',
}) async {
  final start = DateTime.tryParse(startDate);
  if (start == null) {
    throw StateError('请先在「学期设置」填写第一周周一的日期');
  }
  final end = start.add(Duration(days: weekCount * 7 - 1));
  String iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  final prompt = '学校校历图片如下。学期第一周周一为 ${iso(start)}，共 $weekCount 周，'
      '学期日期范围 ${iso(start)} 至 ${iso(end)}。'
      '请提取所有影响正常上课的日期安排，输出 JSON 数组，每个元素为以下两种之一：\n'
      '- 放假日（该日放假、不上课）：{"date": "YYYY-MM-DD", "type": "off"}\n'
      '- 调休上课日（因放假，该日按星期 N 的课表上课）：{"date": "YYYY-MM-DD", "type": "follow", "day": N}\n'
      '其中 day 取值 0-6（0=周一，1=周二，……，6=周日）。'
      '日期按图片中的月份结合学期范围推算年份，必须落在学期日期范围内；'
      '连续多天的放假（如国庆假期）逐日展开；原本就休息的正常周末不要输出。';

  final text = await AiVision.I.describeImage(
    image,
    prompt: prompt,
    system: _holidaySystem,
    mime: mime,
    timeout: const Duration(seconds: 120),
    maxTokens: 4096,
  );

  final out = <String, HolidayRule>{};
  for (final item in extractJsonArray(text)) {
    if (item is! Map) continue;
    final d = DateTime.tryParse('${item['date']}'.trim());
    if (d == null) continue;
    final day0 = DateTime(d.year, d.month, d.day);
    if (day0.isBefore(DateTime(start.year, start.month, start.day)) ||
        day0.isAfter(DateTime(end.year, end.month, end.day))) {
      continue;
    }
    final key = iso(day0);
    if (item['type'] == 'off') {
      out[key] = HolidayRule(date: key, type: 'off');
    } else if (item['type'] == 'follow') {
      final n = int.tryParse('${item['day']}');
      if (n != null && n >= 0 && n <= 6) {
        out[key] = HolidayRule(date: key, type: 'follow', day: n);
      }
    }
  }
  final rules = out.keys.toList()..sort();
  return [for (final k in rules) out[k]!];
}

/// 从模型输出里抠出 JSON 数组（可能被 ```json 包裹或前后带解释）。
/// 从模型输出里抠出 JSON 数组（可能被 ```json 包裹或前后带解释）。供测试直接调用。
List<dynamic> extractJsonArray(String text) {
  final cleaned = text.replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '').trim();
  final start = cleaned.indexOf('[');
  final end = cleaned.lastIndexOf(']');
  if (start < 0 || end <= start) return const [];
  try {
    final j = jsonDecode(cleaned.substring(start, end + 1));
    return j is List ? j : const [];
  } catch (_) {
    return const [];
  }
}
