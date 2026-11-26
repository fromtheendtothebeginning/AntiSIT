import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// 写操作「结果是否不确定」的判定口径：**只有明确的拒绝才算失败**。
///
/// 历史症状：电费充值 / 活动报名各自用 `msg.contains('超时') || msg.contains('网络')`
/// 判断——连接重置、502/504 都不含这两个词，于是被报成「失败」，用户当场重试，
/// 而首次请求可能已经扣款 / 已生成申请记录。
void main() {
  group('writeOutcomeUncertain', () {
    test('客户端超时 / 网络中断（ApiError 显式标注）：未确认', () {
      expect(writeOutcomeUncertain(ApiError('请求超时', null, true)), isTrue);
      expect(writeOutcomeUncertain(ApiError('网络错误', null, true)), isTrue);
    });

    test('网关 5xx / 408 / 429：未确认（请求可能已被处理）', () {
      expect(writeOutcomeUncertain(ApiError('请求失败（502）', 502)), isTrue);
      expect(writeOutcomeUncertain(ApiError('请求失败（504）', 504)), isTrue);
      expect(writeOutcomeUncertain(ApiError('请求失败（500）', 500)), isTrue);
      expect(writeOutcomeUncertain(ApiError('请求失败（408）', 408)), isTrue);
      expect(writeOutcomeUncertain(ApiError('请求失败（429）', 429)), isTrue);
    });

    test('明确的 4xx 拒绝：确定失败，可以放心提示重试', () {
      expect(writeOutcomeUncertain(ApiError('参数错误', 400)), isFalse);
      expect(writeOutcomeUncertain(ApiError('登录已过期', 401)), isFalse);
      expect(writeOutcomeUncertain(ApiError('无权限', 403)), isFalse);
      expect(writeOutcomeUncertain(ApiError('余额不足', 402)), isFalse);
    });

    test('学校业务错误（无 HTTP code 的 ApiError）：确定失败', () {
      expect(writeOutcomeUncertain(ApiError('余额不足，充值失败')), isFalse);
      expect(writeOutcomeUncertain(ApiError('二维码已失效')), isFalse);
    });

    test('非 ApiError（解析崩溃等）：按未确认处理，绝不诱导重试', () {
      expect(writeOutcomeUncertain(StateError('boom')), isTrue);
      expect(writeOutcomeUncertain(FormatException('bad')), isTrue);
    });

    test('显式标注优先于 code 推断', () {
      expect(writeOutcomeUncertain(ApiError('隧道未建立', 202, false)), isFalse);
    });
  });
}
