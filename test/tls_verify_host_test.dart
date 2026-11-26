import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// TLS 主机名校验的回归：**必须按 DNS 标签边界比对**。
///
/// 历史症状：`verifyHost` 用 `text.contains(want)` 与 `text.contains('.sit.edu.cn')`
/// 做纯子串匹配，于是伪造证书里写 `a.jwxt.sit.edu.cn.attacker.tld` 就能通过校验。
/// 这条链路本身就是「没有 SNI、靠自行核对证书」的自签兜底，一旦能被绕过，
/// 校园网内的中间人就能把统一认证密码骗走。
void main() {
  group('certNameMatches：完全相同 / 通配符 / 整域证书', () {
    test('完全相同', () {
      expect(certNameMatches('jwxt.sit.edu.cn', 'jwxt.sit.edu.cn'), isTrue);
      expect(certNameMatches('JWXT.SIT.EDU.CN', 'jwxt.sit.edu.cn'), isTrue);
      expect(certNameMatches('jwxt.sit.edu.cn.', 'jwxt.sit.edu.cn'), isTrue);
    });

    test('通配符只覆盖一级子域', () {
      expect(certNameMatches('*.sit.edu.cn', 'jwxt.sit.edu.cn'), isTrue);
      expect(certNameMatches('*.sit.edu.cn', 'a.b.sit.edu.cn'), isFalse,
          reason: '通配符不能跨级');
      expect(certNameMatches('*.sit.edu.cn', 'sit.edu.cn'), isFalse,
          reason: '通配符不能覆盖裸域');
      expect(certNameMatches('*.sit.edu.cn', 'evil-sit.edu.cn'), isFalse);
    });

    test('整域证书覆盖子域，但必须是 ≥3 段的完整域名', () {
      expect(certNameMatches('sit.edu.cn', 'jwxt.sit.edu.cn'), isTrue);
      expect(certNameMatches('sit.edu.cn', 'sit.edu.cn'), isTrue);
      expect(certNameMatches('edu.cn', 'jwxt.sit.edu.cn'), isFalse,
          reason: '顶级域下的二段名不能覆盖一片');
      expect(certNameMatches('cn', 'jwxt.sit.edu.cn'), isFalse);
    });

    test('后缀之外的域名不能命中（旧实现的漏洞）', () {
      const forged = [
        'a.jwxt.sit.edu.cn.attacker.tld',
        'jwxt.sit.edu.cn.attacker.tld',
        'sit.edu.cn.evil.com',
        'notsit.edu.cn',
        'jwxt-sit.edu.cn',
      ];
      for (final name in forged) {
        expect(certNameMatches(name, 'jwxt.sit.edu.cn'), isFalse,
            reason: '「$name」不该被当成 jwxt.sit.edu.cn 的合法证书');
      }
    });

    test('子域反向不命中：目标更短的父域不会被更长证书名覆盖', () {
      expect(certNameMatches('jwxt.sit.edu.cn', 'sit.edu.cn'), isFalse);
      expect(certNameMatches('a.b.c.d', 'd'), isFalse);
    });

    test('空值一律不命中', () {
      expect(certNameMatches('', 'jwxt.sit.edu.cn'), isFalse);
      expect(certNameMatches('jwxt.sit.edu.cn', ''), isFalse);
      expect(certNameMatches('', ''), isFalse);
    });
  });
}
