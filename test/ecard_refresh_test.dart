import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ecard/plugin_ecard.dart';

/// 校园码刷新节奏：服务端 `refresh` 标的是码的有效期（现在回 55），
/// 客户端封顶 30 秒 + 提前 3 秒换码——手里的码总是新的。
void main() {
  group('校园码刷新倒计时', () {
    test('服务端的 55 秒被压到 30 秒（提前 3 秒换码 → 倒计时 27）', () {
      expect(ecardCountdownSeconds(55), 27);
      expect(ecardCountdownSeconds(55), lessThan(30));
    });

    test('服务端没给 refresh 时也按 30 秒算', () {
      expect(ecardCountdownSeconds(null), 27);
    });

    test('服务端给得更短就听服务端的（别显示一张已经过期的码）', () {
      expect(ecardCountdownSeconds(20), 17);
      expect(ecardCountdownSeconds(10), 7);
    });

    test('再短的码也留 5 秒，不至于一秒一变', () {
      expect(ecardCountdownSeconds(5), 5);
      expect(ecardCountdownSeconds(1), 5);
      expect(ecardCountdownSeconds(0), 5);
    });
  });
}
