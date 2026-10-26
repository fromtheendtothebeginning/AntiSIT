import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归用例：工具卡面速览的数值可能是字符串（学工 /score 的 zxs、sjxf 就是 "8.0"），
/// 只认 num 会让「二课分数」卡显示 0 / 0。
void main() {
  test('二课分数：字符串型 credit / total 正常解析', () {
    final s = ToolCache.scoreOf({'credit': '5.5', 'total': '8.0'})!;
    expect(s.credit, 5.5);
    expect(s.total, 8.0);
  });

  test('二课分数：数字型保持原样，缺字段按 0', () {
    final s = ToolCache.scoreOf({'credit': 3, 'total': 6})!;
    expect(s.credit, 3);
    expect(s.total, 6);
    final empty = ToolCache.scoreOf(<String, dynamic>{})!;
    expect(empty.credit, 0);
    expect(empty.total, 0);
  });

  test('电费余额：字符串型同样解析', () {
    final e = ToolCache.electricityOf({'balance': '12.34'})!;
    expect(e.balance, 12.34);
  });
}
