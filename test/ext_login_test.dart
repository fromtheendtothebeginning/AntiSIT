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

    test('退出登录走 login.clear：删除这些域的 Cookie', () async {
      // 桌面 / 测试环境没有 CookieManager：应报「只支持 Android」而不是静默成功，
      // 免得拓展以为账号已经退出了。
      if (ExtCookieBridge.supported) return;
      expect(
        () => ExtCookieBridge.remove(const ['https://chaoxing.com']),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('父域候选：子域能退回主域（父域 Cookie 才是学习通的登录态）', () {
      // CookieManager 删 `.chaoxing.com` 必须带 Domain=，候选要按长度递减排出来。
      // 这里只验「可删域」这层纯逻辑，实际删除在 Android 侧。
      expect(
        ExtCookieBridge.domainCandidates('mooc1-api.chaoxing.com'),
        ['mooc1-api.chaoxing.com', 'chaoxing.com'],
      );
      expect(
        ExtCookieBridge.domainCandidates('passport2.chaoxing.com'),
        ['passport2.chaoxing.com', 'chaoxing.com'],
      );
      expect(
        ExtCookieBridge.domainCandidates('chaoxing.com'),
        ['chaoxing.com'],
      );
      expect(
        ExtCookieBridge.domainCandidates('a.b.c.d.example.com'),
        ['a.b.c.d.example.com', 'b.c.d.example.com', 'c.d.example.com',
          'd.example.com', 'example.com'],
      );
    });

    test('还在登录页时，即使带着旧 Cookie 也不算登录成功', () {
      // 这是「退出后又自己登上」的另一半根因：判定只看 Cookie 时，
      // 登录页一打开就会被自动 capture（CookieStore 里还留着上次的 _uid）。
      expect(
        ExtLoginPage.shouldAutoCapture(
          url: 'https://passport2.chaoxing.com/login?fid=',
          successUrlPrefix: 'https://i.chaoxing.com',
        ),
        isFalse,
        reason: '还在登录页：不能因为 Cookie 里残留 _uid 就判定登录成功',
      );
      expect(
        ExtLoginPage.shouldAutoCapture(
          url: 'https://i.chaoxing.com/base',
          successUrlPrefix: 'https://i.chaoxing.com',
        ),
        isTrue,
        reason: '已经跳到成功页：可以自动完成',
      );
      expect(
        ExtLoginPage.shouldAutoCapture(url: 'https://i.chaoxing.com/base'),
        isTrue,
        reason: '没给前缀时不做门槛（调用方自己判断）',
      );
    });
  });
}
