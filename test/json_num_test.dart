import 'package:flutter_test/flutter_test.dart';

import 'package:campus_service/json_num.dart';

void main() {
  test('asNum 兼容数字与字符串（服务器字段两种形态都出现）', () {
    expect(asNum(12), 12);
    expect(asNum(12.5), 12.5);
    expect(asNum('12.5'), 12.5);
    expect(asNum(' 23.45 '), 23.45);
    expect(asNum(''), isNull);
    expect(asNum('—'), isNull);
    expect(asNum(null), isNull);
    expect(asNum(true), isNull);
  });

  test('asInt / asDouble 换算', () {
    expect(asInt('55'), 55);
    expect(asInt(2026.0), 2026);
    expect(asDouble('56.70'), 56.7);
    expect(asDouble(null), isNull);
  });
}
