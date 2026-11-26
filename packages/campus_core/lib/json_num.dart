/// 服务器字段宽容取数：数值字段可能是数字或字符串（如 "12.5"），统一安全转 num。
num? asNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

int? asInt(dynamic v) => asNum(v)?.toInt();

double? asDouble(dynamic v) => asNum(v)?.toDouble();
