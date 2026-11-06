import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_score/plugin_score.dart';

/// 第二课堂加分明细：学分是 0.1/0.2/0.5 这类十进制小数，
/// 求和必须用「千分位整数」避免二进制浮点尾巴（曾显示 5.930000000000002）。
void main() {
  test('学分求和按千分位整数累加，不产生浮点误差', () {
    expect(sumCreditThousandths(['0.20', '0.50', '0.30']), 1000);
    expect(sumCreditThousandths(['0.1', '0.2']), 300);
    expect(sumCreditThousandths([0.1, 0.2]), 300);
    expect(sumCreditThousandths(['0.125', '0.125']), 250);
    // 缺学分 / 脏数据跳过，不参与累计
    expect(sumCreditThousandths(['', null, 'abc']), 0);
    // 95 条 0.1 的真实规模：整数累加必须是精确的 9500
    expect(sumCreditThousandths(List.filled(95, '0.1')), 9500);
  });

  test('学分显示抹掉二进制浮点尾巴', () {
    expect(formatCredit(5.930000000000002), '5.93');
    expect(formatCredit(0.7000000000000001), '0.7');
    expect(formatCredit(1.0000000000000002), '1');
    expect(formatCredit(12), '12');
    expect(formatCredit(0.5), '0.5');
    expect(formatCredit(0), '0');
  });
}
