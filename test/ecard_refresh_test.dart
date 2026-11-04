import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_ecard/plugin_ecard.dart';

/// 校园码刷新节奏：默认每 10 秒换一张（可在「我的 → 配置」调整）；
/// 服务端 `refresh` 标的是码的有效期（现在回 55），有效期更短时听服务端的。
void main() {
  group('校园码刷新倒计时', () {
    test('默认每 10 秒换一张，服务端的 55 秒有效期不再决定节奏', () {
      expect(ecardCountdownSeconds(55), 10);
      expect(ecardCountdownSeconds(null), 10);
    });

    test('按配置的间隔换码', () {
      expect(ecardCountdownSeconds(55, interval: 5), 5);
      expect(ecardCountdownSeconds(55, interval: 15), 15);
      expect(ecardCountdownSeconds(55, interval: 30), 30);
    });

    test('服务端有效期更短就听服务端的，并提前 3 秒换码', () {
      expect(ecardCountdownSeconds(8, interval: 10), 5);
      expect(ecardCountdownSeconds(20, interval: 30), 17);
    });

    test('再短的码也留 5 秒，不至于一秒一变', () {
      expect(ecardCountdownSeconds(5, interval: 10), 5);
      expect(ecardCountdownSeconds(1, interval: 10), 5);
      expect(ecardCountdownSeconds(0, interval: 10), 5);
    });
  });
}
