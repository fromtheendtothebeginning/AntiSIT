import 'package:flutter_test/flutter_test.dart';

import 'package:campus_core/campus_core.dart';

/// 假后端：可按需让某次读写抛「密文解不开」，验证自愈兜底。
class _FakeBackend implements SecureStorageBackend {
  _FakeBackend({this.failReads = 0, this.failWrites = false});

  /// 前 N 次 read 抛密钥类异常（模拟 Keystore 别名失效 / 换签名重装）。
  int failReads;
  bool failWrites;
  int deleteAllCalls = 0;
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async {
    if (failReads > 0) {
      failReads--;
      throw Exception(
          'PlatformException(SecurityException, java.security.GeneralSecurityException: '
          'Could not decrypt key. decryption failed)');
    }
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) {
      failWrites = false;
      throw Exception('PlatformException(SecurityException, Could not decrypt key)');
    }
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<void> deleteAll() async {
    deleteAllCalls++;
    data.clear();
  }
}

void main() {
  group('密文解不开时自愈', () {
    test('读抛密钥类异常 → 清空存储重建，返回空而不是崩', () async {
      final backend = _FakeBackend(failReads: 1);
      backend.data['token'] = 'stale-ciphertext';
      final store = FlutterSecureStore(backend: backend);

      expect(await store.read('token'), isNull);
      expect(backend.deleteAllCalls, 1, reason: '解不开就该清空重建');
      expect(backend.data, isEmpty);
    });

    test('写抛密钥类异常 → 同样清空重建，且内存副本仍可读', () async {
      final backend = _FakeBackend(failWrites: true);
      final store = FlutterSecureStore(backend: backend);

      await store.write('token', 'jwt-new');
      expect(backend.deleteAllCalls, 1);
      // 写盘失败不打断登录流程：本次会话从内存副本读得到
      expect(await store.read('token'), 'jwt-new');
    });

    test('同一进程只清一次（不会每条 key 都删一遍）', () async {
      final backend = _FakeBackend(failReads: 3);
      final store = FlutterSecureStore(backend: backend);

      await store.read('a');
      await store.read('b');
      await store.read('c');
      expect(backend.deleteAllCalls, 1);
    });

    test('清过之后后续读走新密钥，能成功', () async {
      final backend = _FakeBackend(failReads: 1);
      final store = FlutterSecureStore(backend: backend);

      await store.read('token'); // 触发一次清理
      await store.write('token', 'jwt-after-heal');
      expect(await store.read('token'), 'jwt-after-heal');
      expect(backend.deleteAllCalls, 1);
    });

    test('非密钥类故障（如超时）不清空存储，避免误删用户凭据', () async {
      final backend = _FakeBackend();
      final store = FlutterSecureStore(backend: backend);
      backend.data['token'] = 'keep-me';

      // 直接把 read 换成一个与密钥无关的异常
      final throwing = _TimeoutBackend(backend);
      final store2 = FlutterSecureStore(backend: throwing);
      expect(await store2.read('token'), isNull);
      expect(throwing.deleteAllCalls, 0, reason: '无关故障不能删用户数据');
      expect(backend.data['token'], 'keep-me');
      expect(await store.read('token'), 'keep-me');
    });
  });
}

/// 抛「超时」的假后端：同样继承计数，便于断言没被清。
class _TimeoutBackend implements SecureStorageBackend {
  _TimeoutBackend(this.inner);
  final _FakeBackend inner;
  int deleteAllCalls = 0;

  @override
  Future<String?> read(String key) async =>
      throw Exception('PlatformException(timeout, took too long)');

  @override
  Future<void> write(String key, String value) async =>
      throw Exception('PlatformException(timeout, took too long)');

  @override
  Future<void> delete(String key) async => inner.delete(key);

  @override
  Future<void> deleteAll() async {
    deleteAllCalls++;
    inner.deleteAll();
  }
}
