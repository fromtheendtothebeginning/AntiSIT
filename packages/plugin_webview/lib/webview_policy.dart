/// 内核里纯逻辑的两件事：主框架导航怎么判、桥垫片怎么进页面。
/// 单独放一个文件是为了能单测——「什么链接该拦、拦了之后干什么」是纯字符串判断。
library;

/// 一次主框架导航的处理方式。
enum NavAction {
  /// 放行：页面自己走（同文档锚点、`data:` / `blob:` / `about:`、iframe 子框架）。
  allow,

  /// 拦下，交给系统浏览器打开——外链不该在带通道的页面里加载。
  openExternal,

  /// 拦下且不打开（`file:` / `intent:` 这类网页里不该出现的方案）。
  block,
}

/// 主框架导航判定：子框架一律放行；网址形态正常浏览。
/// 内联 html（压缩包拓展）只允许本地方案——主框架跳走即「用户点了外链」，拦下交系统浏览器，
/// 否则内核每次 onPageFinished 重注入的垫片会连带交给外部站点。
NavAction decideMainFrameNavigation(
  String url, {
  required bool isMainFrame,
  required bool fromInlineHtml,
}) {
  if (!isMainFrame) return NavAction.allow;
  if (!fromInlineHtml) return NavAction.allow;

  final scheme = (Uri.tryParse(url.trim())?.scheme ?? '').toLowerCase();
  return switch (scheme) {
    '' || 'about' || 'data' || 'blob' || 'javascript' => NavAction.allow,
    'http' || 'https' => NavAction.openExternal,
    _ => NavAction.block,
  };
}

/// 返回**系统返回键 / 侧滑**时要做什么。
///
/// 这里刻意**不看浏览历史**：融合门户的登录页一退回就自动重新登录并压栈，历史里
/// 永远有「上一页」，按 canGoBack 拦下来的话返回键就永远退不出去（用户反馈的
/// 「登录状态下无法退出」）。所以返回键只认网页自己的页面栈（拓展 ctx.ui.push），
/// 栈空就关整页；站内前后翻页交给工具栏的「后退 / 前进」按钮。
enum BackAction {
  /// 交给网页的 `window.__antiSITBack()`（拓展叠的子页面）。
  webStack,

  /// 回退 WebView 的浏览历史（只有工具栏的「后退」会这么判）。
  webHistory,

  /// 关掉这个页面。
  closeRoute,
}

BackAction decideBackAction({required bool hasWebStackPage}) {
  return hasWebStackPage ? BackAction.webStack : BackAction.closeRoute;
}

/// 页内工具栏「后退」按钮：有浏览历史就退一层。
BackAction decideHistoryBack({required bool canGoBackHistory}) =>
    canGoBackHistory ? BackAction.webHistory : BackAction.closeRoute;

/// 当前页面是否还能使用桥接能力：内联 html 允许；网址形态只允许与初始页同源。
/// JS 通道不随导航消失，不同源时必须在这里拒绝，否则外部页面能直接调 `antiSITBridge`。
bool bridgeAllowedOnPage({
  required String? currentUrl,
  required String initialUrl,
  required bool fromInlineHtml,
}) {
  if (fromInlineHtml) return true;
  final current = Uri.tryParse(currentUrl?.trim() ?? '');
  final initial = Uri.tryParse(initialUrl.trim());
  if (current == null || initial == null) return false;
  // Uri.origin 只对 http/https 有效，对 about:/data: 会直接抛错。
  String? originOf(Uri u) =>
      (u.scheme == 'http' || u.scheme == 'https') ? u.origin : null;
  final a = originOf(current);
  final b = originOf(initial);
  if (a == null || b == null) return false;
  return a == b;
}

/// 把桥垫片写进 html 本身，让页面的第一个同步脚本就能用 antiSIT。
/// 插在 `<head>` 之后（没有则 `<!doctype>` 之后，都没有才放最前——放在 doctype 前会退回怪异模式）。
String injectBridgeShim(String html, String shim) {
  if (shim.trim().isEmpty) return html;
  final script = '<script>$shim</script>';
  final head = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(html);
  if (head != null) return html.replaceRange(head.end, head.end, script);
  final doctype = RegExp(
    r'<!doctype[^>]*>',
    caseSensitive: false,
  ).firstMatch(html);
  if (doctype != null) return html.replaceRange(doctype.end, doctype.end, script);
  return '$script$html';
}
