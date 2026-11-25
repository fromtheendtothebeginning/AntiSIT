import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_core/campus_core.dart';

import 'publish_models.dart';

/// 发布设置与密钥：配置走 SharedPreferences，Token / 私钥走 [SecureStore]。
///
/// Token 与签名私钥属于「泄露就能冒充作者」的凭据，不能落明文。
class PublishSettings {
  PublishSettings._();

  static const String _configKey = 'plugin.ext.publish.config';
  static const String _keyKey = 'plugin.ext.publish.key';
  static String _tokenKey(PublishProvider p) => 'plugin.ext.publish.token.${p.name}';

  static Future<PublishConfig?> loadConfig() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_configKey);
    if (raw == null) return null;
    try {
      return PublishConfig.tryParse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveConfig(PublishConfig config) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_configKey, jsonEncode(config.toJson()));
  }

  static Future<String?> readToken(PublishProvider provider) =>
      SecureStore.I.read(_tokenKey(provider));

  static Future<void> writeToken(PublishProvider provider, String? token) async {
    final value = (token ?? '').trim();
    if (value.isEmpty) {
      await SecureStore.I.remove(_tokenKey(provider));
      return;
    }
    await SecureStore.I.write(_tokenKey(provider), value);
  }

  /// 当前发布密钥；没有就生成一对（Ed25519，私钥进 SecureStore）。
  static Future<PublishKey> ensureKey() async {
    final existing = await _readKey();
    if (existing != null) return existing;
    final pair = await Ed25519().newKeyPair();
    final pub = await pair.extractPublicKey();
    final key = PublishKey(
      keyId: 'author',
      privateKey: base64Encode(await pair.extractPrivateKeyBytes()),
      publicKey: base64Encode(pub.bytes),
    );
    await SecureStore.I.write(_keyKey, jsonEncode(key.toJson()));
    return key;
  }

  /// 只读现有密钥（页面打开时显示指纹用）；没有返回 null。
  static Future<PublishKey?> readKey() => _readKey();

  static Future<PublishKey?> _readKey() async {
    final raw = await SecureStore.I.read(_keyKey);
    if (raw == null) return null;
    try {
      return PublishKey.tryParse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }
}
