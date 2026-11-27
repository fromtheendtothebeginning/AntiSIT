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

/// 一次返回请求该由谁处理。三层优先级：网页自己的页面栈（拓展的 ctx.ui.push）→
/// WebView 的浏览历史（融合门户这类站点内部点进去还是有前一页）→ 关掉整页。
enum BackAction {
  /// 交给网页的 `window.__antiSITBack()`（拓展叠的子页面）。
  webStack,

  /// 网页没有自己的栈，但 WebView 还有上一页：回退一层，别把整页关掉。
  webHistory,

  /// 都没得退：关掉这个页面。
  closeRoute,
}

BackAction decideBackAction({
  required bool hasWebStackPage,
  required bool canGoBackHistory,
}) {
  if (hasWebStackPage) return BackAction.webStack;
  if (canGoBackHistory) return BackAction.webHistory;
  return BackAction.closeRoute;
}

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
