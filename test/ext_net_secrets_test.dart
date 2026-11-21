import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  group('校内明文 http 通道（net.campus）', () {
    test('只接受 http：https / 其它协议一律拒', () {
      for (final url in [
        'https://210.35.98.35:8003/',
        'ftp://210.35.98.35/',
        'not a url',
        'http://user:pw@210.35.98.35:8003/',
      ]) {
        expect(() => ExtNetService.I.validateCampusUrl(url),
            throwsA(isA<ExtNetException>()),
            reason: '$url 不该通过');
      }
    });

    test('仍然拒绝本机 / 回环 / 链路本地 / CGNAT（但放行内网）', () async {
      for (final host in [
        'localhost',
        '127.0.0.1',
        '169.254.1.1',
        '100.64.0.1',
      ]) {
        expect(() => ExtNetService.I.validateCampusUrl('http://$host/'),
            throwsA(isA<ExtNetException>()),
            reason: '$host 不该通过');
      }
      // 校内地址是普通内网段：campus 通道要放行（网络不通会在连接阶段报错，
      // 而不是在校验阶段被拦）
      final uri = await ExtNetService.I.validateCampusUrl('http://10.1.2.3:8003/');
      expect(uri.host, '10.1.2.3');
    });

    test('回环判定与公网段互不误伤', () {
      for (final ip in [
        '127.0.0.1',
        '0.0.0.0',
        '169.254.1.1',
        '100.64.0.1',
        '224.0.0.1',
        '::1',
        'fe80::1',
        'fc00::1',
      ]) {
        expect(ExtNetService.isLoopbackOrLinkLocal(InternetAddress(ip)), isTrue,
            reason: '$ip 应该被拦下');
      }
      for (final ip in ['10.1.2.3', '210.35.98.35', '172.16.0.1', '8.8.8.8']) {
        expect(ExtNetService.isLoopbackOrLinkLocal(InternetAddress(ip)), isFalse,
            reason: '$ip 不该被误伤');
      }
    });

    test('经代理的请求头用 absolute-form（路径形式会被代理回 400）', () {
      final head = ExtNetService.buildProxyHead(
        method: 'POST',
        uri: Uri.parse('http://210.35.98.35:8003/Login/RemoteUserLogin?a=1'),
        headers: const {'User-Agent': 'AntiSIT-Ext/1.0', 'Cookie': 'ASP.NET_SessionId=x'},
        contentLength: 12,
      );
      expect(head.split('\r\n').first,
          'POST http://210.35.98.35:8003/Login/RemoteUserLogin?a=1 HTTP/1.1');
      expect(head, contains('Host: 210.35.98.35:8003'));
      expect(head, contains('Cookie: ASP.NET_SessionId=x'));
      expect(head, contains('Content-Length: 12'));
      expect(head.endsWith('\r\n\r\n'), isTrue);
    });

    test('解析代理响应：状态、set-cookie 与正文', () {
      final raw = utf8.encode('HTTP/1.1 200 OK\r\n'
          'Content-Type: application/json; charset=utf-8\r\n'
          'Set-Cookie: ASP.NET_SessionId=abc; path=/; HttpOnly\r\n'
          '\r\n'
          '{"IsSuccess":true}');
      final res = ExtNetService.parseProxyResponse(
          Uint8List.fromList(raw), Uri.parse('http://210.35.98.35:8003/'));
      expect(res['status'], 200);
      expect(res['text'], '{"IsSuccess":true}');
      expect((res['setCookies'] as List).single, contains('ASP.NET_SessionId=abc'));
      expect((res['headers'] as Map)['Content-Type'],
          'application/json; charset=utf-8');
      expect(res['truncated'], isFalse);
    });

    test('隧道代理地址解析', () {
      expect(ExtNetService.parseProxyUrl('http://anticraft.top:10004'),
          (host: 'anticraft.top', port: 10004));
      expect(ExtNetService.parseProxyUrl('anticraft.top:10004/'),
          (host: 'anticraft.top', port: 10004));
      expect(ExtNetService.parseProxyUrl(''), isNull);
      expect(ExtNetService.parseProxyUrl('anticraft.top'), isNull);
      expect(ExtNetService.parseProxyUrl('http://:10004'), isNull);
      expect(ExtNetService.parseProxyUrl('http://h:70000'), isNull);
    });
  });

  group('权限门', () {
    test('net.campus 需要 campus_net，且它是敏感权限', () {
      expect(kMethodPermissions['net.campus'], 'campus_net');
      expect(kSensitivePermissions.contains('campus_net'), isTrue);
      expect(kPermissionLabels['campus_net'], contains('http'));
    });

    test('install 说明按固定顺序列出敏感权限', () {
      expect(
        describeSensitivePermissions(['campus_net', 'storage', 'theme']),
        [
          kPermissionLabels['storage'],
          kPermissionLabels['campus_net'],
        ],
      );
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
