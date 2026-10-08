import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// 校园码底图的像素校验：服务端 `_qr_png_base64` 生成的必须是**透明底**二维码，
/// 否则 App / 网页上会出现「二维码背后一个白色正方形」（用户报过的问题）。
///
/// 这里解码 PNG 的原始像素（png 只有单 IDAT、无隔行，Flutter 测试依赖里没有图像解码器，
/// 所以自己解 zlib + 逐行反滤波），验证角上与静默区透明、深色模块存在且内部留白。
/// 解码后的图像：(宽, 高, RGBA 像素)
typedef _Decoded = ({int width, int height, Uint8List rgba});

_Decoded _pngPixels(Uint8List png) {
  expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], reason: 'PNG 签名');
  var off = 8;
  int width = 0, height = 0, colorType = 0;
  final idat = BytesBuilder();
  while (off < png.length) {
    final len = ByteData.sublistView(png, off, off + 4).getUint32(0);
    final type = String.fromCharCodes(png.sublist(off + 4, off + 8));
    final data = png.sublist(off + 8, off + 8 + len);
    if (type == 'IHDR') {
      final h = ByteData.sublistView(data);
      width = h.getUint32(0);
      height = h.getUint32(4);
      colorType = data[9];
    } else if (type == 'IDAT') {
      idat.add(data);
    }
    off += 12 + len;
  }
  expect(colorType, 6, reason: 'truecolor+alpha（透明底）');
  final raw = Uint8List.fromList(zlib.decode(idat.takeBytes()));
  const bpp = 4;
  final stride = width * bpp;
  final out = Uint8List(height * stride);
  for (var y = 0; y < height; y++) {
    final filter = raw[y * (stride + 1)];
    final line = raw.sublist(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (var x = 0; x < stride; x++) {
      final a = x >= bpp ? out[y * stride + x - bpp] : 0;
      final b = y > 0 ? out[(y - 1) * stride + x] : 0;
      final c = (x >= bpp && y > 0) ? out[(y - 1) * stride + x - bpp] : 0;
      final v = switch (filter) {
        0 => line[x],
        1 => line[x] + a,
        2 => line[x] + b,
        3 => line[x] + ((a + b) >> 1),
        4 => line[x] + _paeth(a, b, c),
        _ => throw StateError('未知 PNG 滤波 $filter'),
      };
      out[y * stride + x] = v & 0xff;
    }
  }
  return (width: width, height: height, rgba: out);
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

void main() {
  test('服务端校园码 PNG 为透明底：角上/静默区透明、模块为黑', () {
    final file = File('test/fixtures/ecard_qr_transparent.png');
    expect(file.existsSync(), isTrue,
        reason: 'fixture 缺失：用 index 后端生成（见 test/fixtures/README 说明）');
    final png = file.readAsBytesSync();
    final decoded = _pngPixels(png);
    final px = decoded.rgba;
    final w = decoded.width;
    final h = decoded.height;
    expect(w, greaterThan(0));
    expect(h, w, reason: '二维码是正方形');
    int alphaAt(int x, int y) => px[(y * w + x) * 4 + 3];

    expect(alphaAt(0, 0), 0, reason: '左上角应透明（原来是白方块）');
    expect(alphaAt(w - 1, 0), 0, reason: '右上角应透明');
    expect(alphaAt(0, h - 1), 0, reason: '左下角应透明');
    expect(alphaAt(w - 1, h - 1), 0, reason: '右下角应透明');

    // 静默区（border=4 模块 × box=10 = 40px）整体透明
    var opaqueInQuiet = 0;
    for (var y = 0; y < 40; y++) {
      for (var x = 0; x < 40; x++) {
        if (alphaAt(x, y) != 0) opaqueInQuiet++;
      }
    }
    expect(opaqueInQuiet, 0, reason: '静默区不该有不透明像素');

    // 有深色模块（不透明），且内部也有留白（不是实心方块）
    var opaqueTotal = 0;
    for (var i = 3; i < px.length; i += 4) {
      if (px[i] != 0) opaqueTotal++;
    }
    expect(opaqueTotal, greaterThan(1000), reason: '二维码模块要画出来');
    expect(opaqueTotal, lessThan(w * h), reason: '底透明白，不能是实心方块');
    expect(alphaAt(w ~/ 2, h ~/ 2), anyOf(0, 255));
  });

  test('后端返回的 dataURI 也能被 App 解析（保持兼容）', () {
    final b64 = base64Encode(File('test/fixtures/ecard_qr_transparent.png').readAsBytesSync());
    final uri = 'data:image/png;base64,$b64';
    final bytes = base64Decode(uri.contains(',') ? uri.split(',').last : uri);
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });
}
