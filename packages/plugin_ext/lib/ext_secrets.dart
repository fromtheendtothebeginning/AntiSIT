/// 拓展的加密凭据存储：Cookie / Token 这类敏感值走系统 Keystore（Android）
/// 或 Keychain（iOS），按拓展 id 隔离。
///
/// 普通数据仍用 `ctx.storage`（明文 SharedPreferences）；这里只放"丢了会被冒用"的值。
library;

import 'package:campus_core/campus_core.dart';

class ExtSecrets {
  static String _storageKey(String extId, String key) =>
      'plugin.ext.secret.$extId.$key';

  static Future<String?> get(String extId, String key) =>
      SecureStore.I.read(_storageKey(extId, key));

  static Future<void> set(String extId, String key, String value) =>
      SecureStore.I.write(_storageKey(extId, key), value);

  static Future<void> remove(String extId, String key) =>
      SecureStore.I.remove(_storageKey(extId, key));

  /// 键名限制成短标识，避免把整段 JSON 当 key 或写出奇怪的前缀。
  static bool validKey(String key) =>
      key.isNotEmpty &&
      key.length <= 128 &&
      RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(key);
}
