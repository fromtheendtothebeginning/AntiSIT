/// 第二课堂加分明细的学分求和 / 显示。
///
/// 学校返回的每条加分记录是 0.1 / 0.2 / 0.5 这类十进制小数，用 double 直接累加
/// 会出现二进制浮点尾巴（0.1 + 0.2 = 0.30000000000000004，页面上曾显示
/// 5.930000000000002）。这里统一按「千分位整数」累加，再换算回学分显示，
/// 保证 5.93、0.7、12 这类值原样输出。
library;

/// 把若干学分（数字或 "0.20" 这样的字符串）按千分位整数累加。
/// 无法解析的值跳过（缺学分的记录本来就不参与累计）。
int sumCreditThousandths(Iterable<Object?> credits) {
  var total = 0;
  for (final raw in credits) {
    final num? n = raw is num ? raw : num.tryParse('${raw ?? ''}'.trim());
    if (n == null) continue;
    total += (n * 1000).round();
  }
  return total;
}

/// 学分显示：先按千分位取整再输出，抹掉二进制浮点尾巴。
String formatCredit(num v) {
  final rounded = (v * 1000).round() / 1000;
  return rounded == rounded.roundToDouble()
      ? rounded.round().toString()
      : rounded.toString();
}
