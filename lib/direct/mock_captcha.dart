import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// 调试用本地模拟服务的图形验证码：把 4 位数字画成 PNG。
// 学校系统的 /kaptcha 与 /authserver/captcha.html 都返回图片，模拟服务得给出真图片，
// App 的验证码弹窗才走得到「显示图片 → 手输 → 提交」这条正常路径。
// 只用 dart:io 的 zlib 手写 PNG，不引入图像库。

/// 5x7 点阵数字（'#' 为笔画），按 0-9 顺序。
const List<List<String>> _glyphs = [
  ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'],
  ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
  ['#####', '...#.', '..#..', '...#.', '....#', '#...#', '.###.'],
  ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
  ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
  ['..##.', '.#...', '#....', '####.', '#...#', '#...#', '.###.'],
  ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
  ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
  ['.###.', '#...#', '#...#', '.####', '....#', '...#.', '.##..'],
];

const int _scale = 5;
const int _pad = 10;
const int _gap = 5;

/// 随机 4 位数字验证码（与学校系统一样是纯数字，长度固定便于测试）。
String randomCaptchaCode([Random? rng]) {
  final r = rng ?? Random();
  return List<String>.generate(4, (_) => '${r.nextInt(10)}').join();
}

/// 渲染验证码图片：浅灰底 + 深蓝数字 + 两条干扰线。
Uint8List renderCaptchaPng(String code, {Random? rng}) {
  final r = rng ?? Random();
  final glyphW = 5 * _scale;
  final glyphH = 7 * _scale;
  final width = _pad * 2 + code.length * glyphW + (code.length - 1) * _gap;
  final height = _pad * 2 + glyphH;
  final px = Uint8List(width * height * 4);

  void put(int x, int y, int rr, int gg, int bb) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    final i = (y * width + x) * 4;
    px[i] = rr;
    px[i + 1] = gg;
    px[i + 2] = bb;
    px[i + 3] = 255;
  }

  for (var i = 0; i < width * height; i++) {
    put(i % width, i ~/ width, 246, 247, 250); // 底：浅灰
  }

  // 干扰线：低对比度，不影响读数字
  for (var k = 0; k < 2; k++) {
    var x = -5;
    var y = r.nextInt(height);
    final slope = r.nextBool() ? 1 : -1;
    while (x < width + 5) {
      put(x, y, 190, 200, 215);
      x++;
      if (r.nextInt(3) == 0) y += slope;
    }
  }

  for (var i = 0; i < code.length; i++) {
    final g = _glyphs[int.tryParse(code[i]) ?? 0];
    final ox = _pad + i * (glyphW + _gap);
    final oy = _pad + r.nextInt(3) - 1; // 每个字轻微上下浮动
    for (var row = 0; row < 7; row++) {
      for (var col = 0; col < 5; col++) {
        if (g[row][col] != '#') continue;
        for (var dy = 0; dy < _scale; dy++) {
          for (var dx = 0; dx < _scale; dx++) {
            put(ox + col * _scale + dx, oy + row * _scale + dy, 30, 58, 138);
          }
        }
      }
    }
  }
  return _encodePng(width, height, px);
}

// ==================== 最小 PNG 编码 ====================

Uint8List _encodePng(int width, int height, Uint8List rgba) {
  final ihdr = BytesBuilder()
    ..add(_u32(width))
    ..add(_u32(height))
    ..add([8, 6, 0, 0, 0]); // 8bit / RGBA / 无隔行
  final raw = BytesBuilder();
  final stride = width * 4;
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // 每行滤波类型 none
    raw.add(Uint8List.sublistView(rgba, y * stride, (y + 1) * stride));
  }
  final idat = ZLibCodec(level: 6).encode(raw.takeBytes());
  final out = BytesBuilder();
  out.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  out.add(_chunk('IHDR', ihdr.takeBytes()));
  out.add(_chunk('IDAT', Uint8List.fromList(idat)));
  out.add(_chunk('IEND', Uint8List(0)));
  return out.takeBytes();
}

List<int> _chunk(String type, Uint8List data) {
  final body = <int>[...type.codeUnits, ...data];
  return [..._u32(data.length), ...body, ..._u32(_crc32(body))];
}

List<int> _u32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
