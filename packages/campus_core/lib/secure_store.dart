import 'package:flutter/foundation.dart';
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

/// 底层加密存储的最小接口：真机是 [FlutterSecureStorage]，测试注入假实现。
abstract interface class SecureStorageBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

class _PlatformBackend implements SecureStorageBackend {
  const _PlatformBackend(this._s);

  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
  @override
  Future<void> deleteAll() => _s.deleteAll();
}

/// 生产实现：Android Keystore / iOS Keychain / Windows DPAPI。
class FlutterSecureStore implements SecureStore {
  FlutterSecureStore({SecureStorageBackend? backend})
      : _storage = backend ?? const _PlatformBackend(_secureStorage);

  /// 显式写 `resetOnError`：插件默认就是 true，但这是「密文解不开就清空重建」
  /// 的兜底开关，写出来免得哪天默认值变了悄悄退化成一直读空。
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );

  final SecureStorageBackend _storage;

  /// 进程内副本：Keystore 偶发失败时本次会话仍可用。
  final Map<String, String> _mem = {};

  /// 本进程已经清过一次存储：避免每条 key 失败都删一遍。
  bool _resetDone = false;

  /// 密钥类故障：Keystore 别名失效 / 换签名重装 / 模拟器快照回滚，
  /// 都会让历史密文**永远**解不开（Android 侧表现为 SecurityException:
  /// Could not decrypt key）。这种情况下留着旧密文只会让每次冷启动都读空、
  /// 用户反复「莫名掉登录态」，所以整个清掉让插件重建密钥。
  static bool _isKeyLost(Object e) {
    final msg = '$e';
    return msg.contains('decrypt') ||
        msg.contains('SecurityException') ||
        msg.contains('GeneralSecurityException') ||
        msg.contains('KeyStore') ||
        msg.contains('AEADBadTag');
  }

  /// 解不开就清空重建（同一进程只做一次）。
  ///
  /// 只删盘上的坏密文，**不清 [_mem]**：本次会话里写进去的值是眼下唯一可用的副本。
  Future<void> _resetIfKeyLost(Object e) async {
    if (!_isKeyLost(e)) return;
    if (_resetDone) return;
    _resetDone = true;
    debugPrint('[安全存储] 密文解不开，清空重建：$e');
    try {
      await _storage.deleteAll();
    } catch (_) {
      // 连清理都失败：本次会话退化成纯内存，下次启动再试
    }
  }

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key) ?? _mem[key];
    } catch (e) {
      await _resetIfKeyLost(e);
      return _mem[key];
    }
  }

  @override
  Future<void> write(String key, String value) async {
    _mem[key] = value;
    try {
      await _storage.write(key, value);
    } catch (e) {
      await _resetIfKeyLost(e);
      // 写盘失败不打断登录/配置流程，内存副本仍可用
    }
  }

  @override
  Future<void> remove(String key) async {
    _mem.remove(key);
    try {
      await _storage.delete(key);
    } catch (e) {
      await _resetIfKeyLost(e);
    }
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
