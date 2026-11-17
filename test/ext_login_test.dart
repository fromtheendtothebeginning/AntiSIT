import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ext/plugin_ext.dart';

void main() {
  group('登录地址校验', () {
    test('只接受 https 且不带账号密码', () {
      expect(ExtLoginPage.parseHttpsUrl('https://example.com/login').host,
          'example.com');
      expect(() => ExtLoginPage.parseHttpsUrl('http://example.com'),
          throwsFormatException);
      expect(() => ExtLoginPage.parseHttpsUrl('https://a:b@example.com'),
          throwsFormatException);
      expect(() => ExtLoginPage.parseHttpsUrl('not a url'),
          throwsFormatException);
    });

    test('cookieUrls 必须同站', () {
      expect(
          ExtLoginPage.sameSite(
              'passport2.chaoxing.com', 'mooc1-api.chaoxing.com'),
          isTrue);
      expect(ExtLoginPage.sameSite('chaoxing.com', 'example.com'), isFalse);
      expect(ExtLoginPage.sameSite('a.example.com', 'b.example.com'), isTrue);
      // .edu.cn 是公共后缀，不能让两所学校被当成同站
      expect(ExtLoginPage.sameSite('a.edu.cn', 'b.edu.cn'), isFalse);
      expect(
          ExtLoginPage.sameSite(
              'passport2.school.edu.cn', 'school.edu.cn'),
          isTrue);
    });

    test('Cookie 头从宽到窄覆盖', () {
      final header = ExtCookieBridge.mergeHeaders(
        {
          'https://chaoxing.com': '_uid=1; uf=old',
          'https://mooc1.chaoxing.com': 'uf=new; fid=42',
        },
        const ['https://chaoxing.com', 'https://mooc1.chaoxing.com'],
      );
      expect(header, '_uid=1; uf=new; fid=42');
    });
  });
}
