import 'package:flutter_test/flutter_test.dart';

import 'package:plugin_webview/webview_policy.dart';

/// 返回键的三层优先级：网页栈 → 浏览历史 → 关整页。
void main() {
  test('拓展叠了子页面：先退网页自己的栈', () {
    expect(
      decideBackAction(hasWebStackPage: true, canGoBackHistory: true),
      BackAction.webStack,
    );
  });

  test('网页没有栈但站点点进去过一页：回退一层，不关整页', () {
    expect(
      decideBackAction(hasWebStackPage: false, canGoBackHistory: true),
      BackAction.webHistory,
    );
  });

  test('都没得退才关掉整页', () {
    expect(
      decideBackAction(hasWebStackPage: false, canGoBackHistory: false),
      BackAction.closeRoute,
    );
  });
}
