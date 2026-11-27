/// 绩点计算器的纯逻辑：哪些课程算通识课、怎么按类别 / 学期分组、加权绩点怎么算。
///
/// 放在独立文件里是为了能单测（页面只负责画勾选框与按钮）。
library;

import 'package:campus_core/campus_core.dart';

/// 一门课在计算器里的唯一键：同名课可能跨学期重修，光用课程名会串。
String courseKeyOf(Map<String, dynamic> g) => [
  '${g['kcmc'] ?? ''}'.trim(),
  '${g['xnmmc'] ?? ''}'.trim(),
  '${g['xqmmc'] ?? ''}'.trim(),
  '${g['xf'] ?? ''}'.trim(),
].join('|');

/// 课程类别标签（正方 `kclbmc`，如「通识课」「学科专业基础课」「专业核心课」）。
String courseTagOf(Map<String, dynamic> g) {
  final t = '${g['kclbmc'] ?? ''}'.trim();
  return t == 'null' ? '' : t;
}

/// 是不是通识课：「除通识课全选」按这个判，学校改名（通识教育 / 通识选修）也认。
bool isGeneralCourse(Map<String, dynamic> g) => courseTagOf(g).contains('通识');

/// 学期标签：`2026-2027学年 · 第一学期`；缺字段时给「未知学期」。
String termLabelOf(Map<String, dynamic> g) {
  final xn = '${g['xnmmc'] ?? ''}'.trim();
  final xq = '${g['xqmmc'] ?? ''}'.trim();
  final parts = [xn, xq].where((s) => s.isNotEmpty && s != 'null').toList();
  return parts.isEmpty ? '未知学期' : parts.join(' · ');
}

/// 可选类别（去重、按出现顺序；空类别不参与筛选）。
List<String> courseTagOptions(Iterable<Map<String, dynamic>> list) {
  final out = <String>[];
  for (final g in list) {
    final t = courseTagOf(g);
    if (t.isNotEmpty && !out.contains(t)) out.add(t);
  }
  return out;
}

/// 可选学期（去重、按出现顺序）。
List<String> termOptions(Iterable<Map<String, dynamic>> list) {
  final out = <String>[];
  for (final g in list) {
    final t = termLabelOf(g);
    if (!out.contains(t)) out.add(t);
  }
  return out;
}

/// 一次计算的结论。
class GpaResult {
  const GpaResult({
    required this.gpa,
    required this.credit,
    required this.count,
    required this.skipped,
  });

  /// 加权绩点 = Σ(绩点 × 学分) / Σ学分；没有可算的课时为 null。
  final double? gpa;

  /// 选中课程的学分合计。
  final double credit;

  /// 真正参与计算的课门数。
  final int count;

  /// 选了但算不进去的门数（缺学分或缺绩点，如成绩「P」）。
  final int skipped;
}

/// 按选中的课算加权绩点。
///
/// 用千分位整数累加再换回小数，避开 `0.1 + 0.2` 的浮点尾巴（与加分明细的学分求和同一套纪律）。
GpaResult computeWeightedGpa(Iterable<Map<String, dynamic>> selected) {
  var sumThousandths = 0; // Σ(绩点×学分) 的千分位
  var creditThousandths = 0; // Σ学分 的千分位
  var count = 0;
  var skipped = 0;
  for (final g in selected) {
    final credit = asNum(g['xf']);
    final point = asNum(g['jd']);
    if (credit == null || point == null) {
      skipped++;
      continue;
    }
    sumThousandths += (point * credit * 1000).round();
    creditThousandths += (credit * 1000).round();
    count++;
  }
  return GpaResult(
    gpa: creditThousandths == 0 ? null : sumThousandths / creditThousandths,
    credit: creditThousandths / 1000,
    count: count,
    skipped: skipped,
  );
}
