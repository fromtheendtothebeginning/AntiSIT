import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';

void main() {
  group('原生 HTTPS 代理的安全约束', () {
    test('拒绝本机 / 内网 / 链路本地 / 保留地址', () {
      for (final ip in [
        '127.0.0.1',
        '10.1.2.3',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.1.1',
        '169.254.1.1',
        '100.64.0.1',
        '0.0.0.0',
        '224.0.0.1',
        '::1',
        'fc00::1',
        'fe80::1',
      ]) {
        expect(ExtNetService.isBlockedAddress(InternetAddress(ip)), isTrue,
            reason: '$ip 应该被拦下');
      }
    });

    test('公网地址放行', () {
      for (final ip in ['8.8.8.8', '1.1.1.1', '2001:4860:4860::8888']) {
        expect(ExtNetService.isBlockedAddress(InternetAddress(ip)), isFalse,
            reason: '$ip 不该被误伤');
      }
    });

    test('过滤底层接管的请求头', () {
      final headers = ExtNetService.sanitizeHeaders({
        'Host': 'evil.example',
        'Content-Length': '999',
        'Connection': 'keep-alive',
        'Cookie': '_uid=1',
        'Authorization': 'Bearer x',
      });
      expect(headers.containsKey('Host'), isFalse);
      expect(headers.containsKey('Content-Length'), isFalse);
      expect(headers.containsKey('Connection'), isFalse);
      expect(headers['Cookie'], '_uid=1');
      expect(headers['Authorization'], 'Bearer x');
    });

    test('只允许 https，且不访问 localhost', () async {
      expect(() => ExtNetService.I.validateUrl('http://example.com'),
          throwsA(isA<ExtNetException>()));
      expect(() => ExtNetService.I.validateUrl('not a url'),
          throwsA(isA<ExtNetException>()));
      expect(() => ExtNetService.I.validateUrl('https://localhost/login'),
          throwsA(isA<ExtNetException>()));
      expect(() => ExtNetService.I.validateUrl('https://127.0.0.1/login'),
          throwsA(isA<ExtNetException>()));
    });
  });

  group('加密凭据', () {
    setUp(() {
      SecureStore.I = MemorySecureStore();
    });

    test('按拓展 id 隔离', () async {
      await ExtSecrets.set('ext.a', 'cookie', 'session=1');
      await ExtSecrets.set('ext.b', 'cookie', 'session=2');
      expect(await ExtSecrets.get('ext.a', 'cookie'), 'session=1');
      expect(await ExtSecrets.get('ext.b', 'cookie'), 'session=2');
      await ExtSecrets.remove('ext.a', 'cookie');
      expect(await ExtSecrets.get('ext.a', 'cookie'), isNull);
      expect(await ExtSecrets.get('ext.b', 'cookie'), 'session=2');
    });

    test('键名限制', () {
      expect(ExtSecrets.validKey('cookie'), isTrue);
      expect(ExtSecrets.validKey('school.cookie_v1'), isTrue);
      expect(ExtSecrets.validKey(''), isFalse);
      expect(ExtSecrets.validKey('a b'), isFalse);
      expect(ExtSecrets.validKey('x' * 129), isFalse);
    });
  });
}
