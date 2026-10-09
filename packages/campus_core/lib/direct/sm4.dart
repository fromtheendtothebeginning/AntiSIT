import 'dart:convert';

import 'sm4_boxes.dart';

// SM4-ECB + PKCS#7 + base64：校付宝支付密码加密。
// 移植自 index 后端 campus/electricity.py（纯算法，未用任何加密库）。

const int _mask = 0xFFFFFFFF;
const String _defaultKey = 'IhaIWKKs9AJpn5ip';
const List<int> _fk = [0xA3B1BAC6, 0x56AA3350, 0x677D9197, 0xB27022DC];

final List<int> _ck = List<int>.generate(32, (i) {
  int b(int j) => (j * 7) % 256;
  return (b(4 * i) << 24) | (b(4 * i + 1) << 16) | (b(4 * i + 2) << 8) | b(4 * i + 3);
});

int _rotl(int x, int n) => ((x << n) | (x >>> (32 - n))) & _mask;

int _tau(int a) =>
    (sm4Sbox[(a >>> 24) & 0xFF] << 24) |
    (sm4Sbox[(a >>> 16) & 0xFF] << 16) |
    (sm4Sbox[(a >>> 8) & 0xFF] << 8) |
    sm4Sbox[a & 0xFF];

int _l(int b) => b ^ _rotl(b, 2) ^ _rotl(b, 10) ^ _rotl(b, 18) ^ _rotl(b, 24);

int _lPrime(int b) => b ^ _rotl(b, 13) ^ _rotl(b, 23);

List<int> _expandKey(List<int> key) {
  final k = <int>[
    for (var i = 0; i < 4; i++) _word(key, i) ^ _fk[i],
  ];
  final rk = <int>[];
  for (var i = 0; i < 32; i++) {
    final v = (k[i] ^ (_lPrime(_tau(k[i + 1] ^ k[i + 2] ^ k[i + 3] ^ _ck[i])) & _mask)) & _mask;
    k.add(v);
    rk.add(v);
  }
  return rk;
}

int _word(List<int> key, int i) =>
    (key[i * 4] << 24) | (key[i * 4 + 1] << 16) | (key[i * 4 + 2] << 8) | key[i * 4 + 3];

List<int> _cryptBlock(List<int> block, List<int> rk) {
  final x = <int>[for (var i = 0; i < 4; i++) _word(block, i)];
  for (var i = 0; i < 32; i++) {
    x.add((x[i] ^ (_l(_tau(x[i + 1] ^ x[i + 2] ^ x[i + 3] ^ rk[i])) & _mask)) & _mask);
  }
  final out = <int>[];
  for (final w in [x[35], x[34], x[33], x[32]]) {
    out.addAll([(w >>> 24) & 0xFF, (w >>> 16) & 0xFF, (w >>> 8) & 0xFF, w & 0xFF]);
  }
  return out;
}

List<int> _padPkcs7(List<int> data) {
  final n = 16 - data.length % 16;
  return [...data, ...List<int>.filled(n, n)];
}

List<int> _unpadPkcs7(List<int> data) {
  if (data.isEmpty || data.length % 16 != 0) throw ArgumentError('密文长度必须是 16 字节的整数倍');
  final n = data.last;
  if (n < 1 || n > 16 || data.sublist(data.length - n).any((b) => b != n)) {
    throw ArgumentError('PKCS#7 填充无效（密钥错误或密文损坏）');
  }
  return data.sublist(0, data.length - n);
}

/// 明文 → SM4-ECB + PKCS#7 + base64。
String sm4Encrypt(String plain, {String key = _defaultKey}) {
  final rk = _expandKey(utf8.encode(key));
  final data = _padPkcs7(utf8.encode(plain));
  final ct = <int>[];
  for (var i = 0; i < data.length; i += 16) {
    ct.addAll(_cryptBlock(data.sublist(i, i + 16), rk));
  }
  return base64Encode(ct);
}

/// base64 密文 → 明文（自检 / 调试用）。
String sm4Decrypt(String b64Cipher, {String key = _defaultKey}) {
  final rk = _expandKey(utf8.encode(key)).reversed.toList();
  final raw = base64Decode(b64Cipher);
  final data = <int>[];
  for (var i = 0; i < raw.length; i += 16) {
    data.addAll(_cryptBlock(raw.sublist(i, i + 16), rk));
  }
  return utf8.decode(_unpadPkcs7(data));
}
