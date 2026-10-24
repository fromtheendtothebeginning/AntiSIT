import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 敏感凭据（登录 token / 账号密码 / 校园凭据——里面还有能直接扣款的支付密码）
/// 的存储口。明文 SharedPreferences 在 root / adb backup / 维修导数据面前裸奔，
/// 这类值一律走这里：真机上是 Keystore 加密的 [FlutterSecureStore]。
///
/// 默认给 [MemorySecureStore]（进程内内存，不持久化）：**flutter_test 里没有平台
/// 实现，平台调用挂起不返回**（不是抛 MissingPluginException，testWidgets 的
/// fake async 又让超时计时器永不到点），所以真机实现必须由宿主 `main()` 显式
/// 装上（见 lib/main.dart），测试不装就自然是内存版，怎么跑都安全。
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);

  /// 宿主 `main()` 装上真机实现（flutter_secure_storage）；测试注入内存假实现。
  static SecureStore I = MemorySecureStore();
}

/// 生产实现：Android Keystore / iOS Keychain / Windows DPAPI
/// （flutter_secure_storage 默认配置）。只应在真机 / 桌面 App 进程里使用。
class FlutterSecureStore implements SecureStore {
  FlutterSecureStore();

  static const _storage = FlutterSecureStorage();

  /// 进程内副本：真机上 Keystore 偶发失败的机型本次会话仍可用（AppState 本就常驻）。
  final Map<String, String> _mem = {};

  @override
  Future<String?> read(String key) async => await _storage.read(key: key) ?? _mem[key];

  @override
  Future<void> write(String key, String value) async {
    _mem[key] = value;
    await _storage.write(key: key, value: value);
  }

  @override
  Future<void> remove(String key) async {
    _mem.remove(key);
    await _storage.delete(key: key);
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
