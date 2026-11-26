import 'ext_secrets.dart';

/// storage / 通知这类接口的 `{key}`：必填非空。
String extArgKey(Object? args) {
  final key = args is Map ? '${args['key'] ?? ''}'.trim() : '';
  if (key.isEmpty) throw ArgumentError('要带 key');
  return key;
}

/// 加密凭据的 key：只允许 1–128 位字母 / 数字 / . _ : -。
String extSecretKey(Object? args) {
  final key = args is Map ? '${args['key'] ?? ''}'.trim() : '';
  if (!ExtSecrets.validKey(key)) {
    throw ArgumentError('密钥名不合法（1–128 位字母 / 数字 / . _ : -）');
  }
  return key;
}

/// 是不是 http(s) 网址（图标字段判「图片网址」用）。
bool isHttpUrl(String s) =>
    s.startsWith('http://') || s.startsWith('https://');

/// 工坊接口的字符串参数：默认不允许空值。
String extArgString(Map<String, Object?> args, String key,
    {bool allowEmpty = false}) {
  final value = '${args[key] ?? ''}'.trim();
  if (!allowEmpty && value.isEmpty) throw ArgumentError('要带 $key');
  return value;
}

/// 原生确认框里的预览文本：超过 1200 字截断。
String extPreviewText(String content) {
  if (content.length <= 1200) return content;
  return '${content.substring(0, 1200)}\n…（共 ${content.length} 字符）';
}
