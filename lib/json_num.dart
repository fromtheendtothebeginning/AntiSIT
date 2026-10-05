/// 服务器字段宽容取数：数值字段可能返回数字也可能返回字符串
/// （校付宝 / 教务接口常见，如 "12.5"），统一安全转成 num，避免运行时类型转换崩溃。
num? asNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

int? asInt(dynamic v) => asNum(v)?.toInt();

double? asDouble(dynamic v) => asNum(v)?.toDouble();
