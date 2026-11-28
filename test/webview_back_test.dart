import 'package:flutter_test/flutter_test.dart';

import 'package:plugin_webview/webview_policy.dart';

/// 返回键与站内前后翻页是两套：返回键不认浏览历史（登录站点历史永远非空）。
void main() {
  test('拓展叠了子页面：返回键先退网页自己的栈', () {
    expect(decideBackAction(hasWebStackPage: true), BackAction.webStack);
  });

  test('网页没有自己的栈：返回键直接关整页，不看浏览历史', () {
    // 融合门户登录页一退回就自动重新登录压栈：按历史拦返回键会永远退不出去。
    expect(decideBackAction(hasWebStackPage: false), BackAction.closeRoute);
  });

  test('工具栏后退：有历史才退一层', () {
    expect(decideHistoryBack(canGoBackHistory: true), BackAction.webHistory);
    expect(decideHistoryBack(canGoBackHistory: false), BackAction.closeRoute);
  });
}
