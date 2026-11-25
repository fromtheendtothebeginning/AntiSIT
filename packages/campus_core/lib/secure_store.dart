import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 敏感凭据（token / 账号密码 / 支付密码 / 会话 Cookie / AI Key）的存储口。
///
/// 默认 [MemorySecureStore]：flutter_test 无平台实现且调用会挂起，真机实现由宿主
/// `main()` 装到 [SecureStore.I]，测试不装就自然是内存版。
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);

  /// 宿主 `main()` 装上真机实现；测试注入内存假实现。
  static SecureStore I = MemorySecureStore();
}

/// 生产实现：Android Keystore / iOS Keychain / Windows DPAPI。
class FlutterSecureStore implements SecureStore {
  FlutterSecureStore();

  static const _storage = FlutterSecureStorage();

  /// 进程内副本：Keystore 偶发失败时本次会话仍可用。
  final Map<String, String> _mem = {};

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key) ?? _mem[key];
    } catch (_) {
      return _mem[key];
    }
  }

  @override
  Future<void> write(String key, String value) async {
    _mem[key] = value;
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // 写盘失败不打断登录/配置流程，内存副本仍可用
    }
  }

  @override
  Future<void> remove(String key) async {
    _mem.remove(key);
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }
}

/// 进程内内存实现（默认）：只活到进程结束，测试与未初始化的兜底。
class MemorySecureStore implements SecureStore {
  final Map<String, String> mem = {};

  @override
  Future<String?> read(String key) async => mem[key];
  @override
  Future<void> write(String key, String value) async => mem[key] = value;
  @override
  Future<void> remove(String key) async => mem.remove(key);
}
