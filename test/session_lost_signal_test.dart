import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自动重登只认「登录态失效」标记，不认文案关键词。
///
/// 历史症状：`_withReloginT` 用 `e.message.contains('失效')` 判断要不要重登重试。
/// 学校的业务失败里也有「二维码已失效」「签到时间已失效」，这些写操作（报名 / 签到）
/// 会被当成会话失效 → 重登 → **再提交一次**，凭空多出一条申请记录。
/// 同理 `xg.dart` 把 `code != 0`（系统繁忙）也当会话失效，把 Cookie 清掉逼用户重登。
void main() {
  test('会话失效有专用标记，业务错误没有', () {
    final lost = ApiError('学工登录已失效，请重新查询', null, null, true);
    expect(lost.sessionLost, isTrue);

    for (final msg in ['二维码已失效', '签到时间已失效', '报名已失效，请重新报名']) {
      final business = ApiError(msg);
      expect(business.sessionLost, isFalse, reason: '「$msg」是业务失败，不能触发重登');
    }
  });

  test('默认构造不带会话失效标记（不会误触发重登）', () {
    expect(ApiError('任何错误').sessionLost, isFalse);
    expect(ApiError('网络错误', null, true).sessionLost, isFalse);
  });

  test('写操作结果未确认与会话失效是两个正交信号', () {
    final lost = ApiError('登录已失效', null, null, true);
    expect(writeOutcomeUncertain(lost), isFalse,
        reason: '会话失效说明请求没被受理，属确定失败');
  });
}
