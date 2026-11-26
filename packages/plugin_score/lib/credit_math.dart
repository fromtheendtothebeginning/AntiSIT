/// 第二课堂加分明细的学分求和 / 显示：按「千分位整数」累加再换算回学分，
/// 避免 double 累加的浮点尾巴（5.930000000000002）。
library;

/// 把若干学分（数字或 "0.20" 这样的字符串）按千分位整数累加；无法解析的值跳过。
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
