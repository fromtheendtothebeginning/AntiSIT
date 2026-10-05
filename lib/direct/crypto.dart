import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

// 校园系统登录/响应加解密：
// - 金智统一认证（authserver）：AES-128-CBC + PKCS#7 加密密码（对齐 index 后端 campus/dekt.py 的 _wisedu_aes）
// - 正方教务：RSA/PKCS#1 v1.5 加密密码（对齐 prepare_jwxt_login 的 modulus/exponent）
// - 部分接口 isEncrypt 响应：AES-128-CBC（key=iv=配置密钥前 16 字节），raw 解密后去尾部 0x00

/// AES-CBC-PKCS7 加密 → 字节；[key]/[iv] 必须为 16 字节。
Uint8List aesCbcPkcs7Encrypt(List<int> plain, List<int> key, List<int> iv) {
  final c = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
  c.init(true, PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
    ParametersWithIV(KeyParameter(Uint8List.fromList(key)), Uint8List.fromList(iv)),
    null,
  ));
  return Uint8List.fromList(c.process(Uint8List.fromList(plain)));
}

/// AES-CBC-PKCS7 解密 → 字节。
Uint8List aesCbcPkcs7Decrypt(List<int> cipher, List<int> key, List<int> iv) {
  final c = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
  c.init(false, PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
    ParametersWithIV(KeyParameter(Uint8List.fromList(key)), Uint8List.fromList(iv)),
    null,
  ));
  return Uint8List.fromList(c.process(Uint8List.fromList(cipher)));
}

/// AES-CBC 原始解密（不校验/不去除填充），去尾部 0x00 后按 UTF-8 解码。
String aesCbcDecryptRawUtf8(List<int> cipher, List<int> key, List<int> iv) {
  final c = CBCBlockCipher(AESEngine())
    ..init(false, ParametersWithIV(KeyParameter(Uint8List.fromList(key)), Uint8List.fromList(iv)));
  final out = Uint8List(cipher.length);
  for (var i = 0; i < cipher.length; i += 16) {
    c.processBlock(Uint8List.fromList(cipher.sublist(i, i + 16)), 0, out, i);
  }
  var end = out.length;
  while (end > 0 && out[end - 1] == 0) {
    end--;
  }
  return utf8.decode(out.sublist(0, end), allowMalformed: true);
}

List<int> _key16(String salt) {
  final b = utf8.encode(salt.trim());
  if (b.length >= 16) return b.sublist(0, 16);
  return [...b, ...List<int>.filled(16 - b.length, 0)];
}

const String _kChars = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

/// 金智统一认证密码加密：AES-CBC-PKCS7，key=salt 前 16 字节，iv=随机 16 字符，
/// 明文 = 随机 64 字符前缀 + 密码，输出 base64。
String wiseduEncryptPassword(String password, String salt, {Random? rng}) {
  final r = rng ?? Random.secure();
  String rds(int n) =>
      String.fromCharCodes(List<int>.generate(n, (_) => _kChars.codeUnitAt(r.nextInt(_kChars.length))));
  final key = _key16(salt);
  final iv = utf8.encode(rds(16));
  return base64Encode(aesCbcPkcs7Encrypt(utf8.encode(rds(64) + password), key, iv));
}

/// `isEncrypt` 响应解密：密钥留空原样返回；解密失败也原样返回（与后端一致）。
String dektDecryptValue(String value, String aesKey) {
  if (aesKey.isEmpty) return value;
  try {
    final key = _key16(aesKey);
    return aesCbcDecryptRawUtf8(base64Decode(value), key, key);
  } catch (_) {
    return value;
  }
}

BigInt _bigIntFromBase64(String b64) {
  final bytes = base64Decode(b64);
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

/// RSA/PKCS#1 v1.5 加密（正方教务密码），[modulusB64]/[exponentB64] 为服务端下发的 base64 大数。
String rsaEncryptPkcs1(String text, String modulusB64, String exponentB64) {
  final pub = RSAPublicKey(_bigIntFromBase64(modulusB64), _bigIntFromBase64(exponentB64));
  final engine = PKCS1Encoding(RSAEngine())
    ..init(true, PublicKeyParameter<RSAPublicKey>(pub));
  return base64Encode(engine.process(Uint8List.fromList(utf8.encode(text))));
}
