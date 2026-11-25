// 一次性脚本：生成模拟校园服务用的 RSA 密钥对，输出粘进 lib/direct/mock_campus_server.dart 的 _rsaModulusB64 / _rsaPrivateB64（dart run tool/gen_mock_rsa.dart）。
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

Uint8List bigIntBytes(BigInt v) {
  final out = <int>[];
  var x = v;
  final mask = BigInt.from(0xFF);
  while (x > BigInt.zero) {
    out.insert(0, (x & mask).toInt());
    x = x >> 8;
  }
  return Uint8List.fromList(out.isEmpty ? [0] : out);
}

void main() {
  final gen = RSAKeyGenerator()
    ..init(ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
      FortunaRandom()..seed(KeyParameter(Uint8List.fromList(List<int>.generate(32, (i) => i * 7 + 1)))),
    ));
  final pair = gen.generateKeyPair();
  final pub = pair.publicKey;
  final priv = pair.privateKey;
  print('modulus (b64): ${base64Encode(bigIntBytes(pub.modulus!))}');
  print('exponent(b64): ${base64Encode(bigIntBytes(pub.exponent!))}');
  print('private (b64): ${base64Encode(bigIntBytes(priv.privateExponent!))}');
}
