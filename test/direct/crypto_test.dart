import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:campus_service/direct/crypto.dart';
import 'package:campus_service/direct/sm4.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

/// 向量来源：
/// - SM4：index 后端 campus/electricity.py（Python 实跑输出）
/// - AES-128-CBC/PKCS7：Node.js crypto（同一算法族，金智 wisedu 密码加密）
/// - RSA：Node.js 生成的 2048 位密钥对（test/direct/fixtures/rsa_key.json）
void main() {
  group('SM4（校付宝支付密码加密）', () {
    test('默认密钥与后端输出逐字节一致', () {
      expect(sm4Encrypt('AntiSIT-直连模式-测试'), 'ZKdbu0qYH3FfldKztOUvRDf5/g++ZZtrpDT4VQieYcg=');
      expect(sm4Encrypt('密码P@ssw0rd!'), 'gJo0KmLirNPafxltE+OEtA==');
    });

    test('自定义密钥与解密往返', () {
      const ct = 'tAlsKWE+QqhMxYOMiS64GgwLp7kDZH3qHZGToHFOENs=';
      expect(sm4Encrypt('自定义key测试', key: '0123456789abcdef'), ct);
      expect(sm4Decrypt(ct, key: '0123456789abcdef'), '自定义key测试');
      expect(sm4Decrypt('ZKdbu0qYH3FfldKztOUvRDf5/g++ZZtrpDT4VQieYcg='), 'AntiSIT-直连模式-测试');
    });
  });

  group('AES-CBC（统一认证密码 + isEncrypt 响应）', () {
    const plain = 'AntiSIT-直连模式-AES-CBC-PKCS7 测试 ✓';
    const ctB64 = 'tgVKkrVOwwmWMC6q49tC6gKvJ7PfDwApPf8ZzgiJN10+AdwtLKJkowR4TEAvfQLo';
    final key = utf8.encode('1234567890abcdef');
    final iv = utf8.encode('fedcba0987654321');

    test('加密结果与 Node.js crypto 一致', () {
      expect(base64Encode(aesCbcPkcs7Encrypt(utf8.encode(plain), key, iv)), ctB64);
    });

    test('解密往返', () {
      expect(utf8.decode(aesCbcPkcs7Decrypt(base64Decode(ctB64), key, iv)), plain);
    });

    test('wisedu 密码加密：随机 64 前缀 + 密码，可同参数还原', () {
      const salt = 'AbCdEfGh12345678'; // 与后端一致：key = salt 前 16 字节
      final ct = wiseduEncryptPassword('P@ssw0rd', salt, rng: Random(42));
      // 复现实现里的随机序列：先 16 字符 IV，再 64 字符前缀
      final r = Random(42);
      const chars = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';
      String draw(int n) =>
          String.fromCharCodes(List<int>.generate(n, (_) => chars.codeUnitAt(r.nextInt(chars.length))));
      final iiv = draw(16);
      final prefix = draw(64);
      final back = utf8.decode(
          aesCbcPkcs7Decrypt(base64Decode(ct), utf8.encode(salt), utf8.encode(iiv)));
      expect(back, '$prefix' 'P@ssw0rd');
      expect(back.length, 64 + 8);
    });

    test('isEncrypt 响应：密钥留空原样返回；零填充密文按 CBC 解密并去尾部 0x00', () {
      expect(dektDecryptValue(ctB64, ''), ctB64);
      // 该校接口用 NoPadding + 零填充，后端 _decrypt_data 即 raw 解密后 rstrip(b"\x00")
      const zeroCt = 'qG8C+Wky2OT+BZySSiTQ6RViieRQjKASXl7OXvD0tnA=';
      expect(aesCbcDecryptRawUtf8(base64Decode(zeroCt), key, iv), 'AntiSIT-isEncrypt-零填充');
    });
  });

  group('RSA/PKCS#1 v1.5（教务密码加密）', () {
    test('公钥加密 → 私钥解密还原（密钥对由 Node.js 生成）', () {
      final fx = jsonDecode(File('test/direct/fixtures/rsa_key.json').readAsStringSync()) as Map;
      final ct = base64Decode(rsaEncryptPkcs1('P@ssw0rd-教务', '${fx['n']}', '${fx['e']}'));

      BigInt big(Object b64) {
        var v = BigInt.zero;
        for (final b in base64Decode('$b64')) {
          v = (v << 8) | BigInt.from(b);
        }
        return v;
      }

      final engine = PKCS1Encoding(RSAEngine())
        ..init(
            false,
            PrivateKeyParameter<RSAPrivateKey>(
                RSAPrivateKey(big(fx['n']), big(fx['d']), big(fx['p']), big(fx['q']))));
      final out = engine.process(ct);
      expect(utf8.decode(out), 'P@ssw0rd-教务');
    });
  });
}
