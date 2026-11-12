/// 内核里**纯逻辑**的那两件事：主框架导航怎么判、桥垫片怎么进页面。
///
/// 单独放一个文件是为了能单测——[WebViewPageState] 里那部分要真机 / 真 WebView 才跑得起来，
/// 而「什么链接该拦、拦了之后干什么」是纯字符串判断，不该跟着一起泡在平台代码里。
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

/// 主框架导航判定。
///
/// * 子框架（iframe）一律放行：那是网页自己的排版，不是「页面跳到别处」；
/// * 网址形态（[fromInlineHtml] 为假）正常浏览——它本来就是网页，用户自己选的站点；
/// * **内联 html**（压缩包拓展）只允许本地方案：它是一份自包含页面，
///   主框架跳走只会是「用户点了外链」。这时既不能带着 `antiSIT` 通道去加载别人的页面
///   （内核每次 `onPageFinished` 都会重注入垫片，跳过去等于把通道交给外面的站点），
///   也不该把用户困在里面——所以拦下、交给系统浏览器。
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

/// 当前页面是否还能使用桥接能力。
///
/// * 内联 html（压缩包拓展）：页面由拓展包提供，允许；
/// * 网址形态：只有当前页与打开时的初始页**同源**才允许。用户从拓展页点到第三方站点后，
///   内核的 JS 通道仍然存在（`addJavaScriptChannel` 不会随导航消失），必须在这里拒绝，
///   否则外部页面可以直接调 `antiSITBridge`，用掉用户的 AI Key / 读写该拓展的 storage。
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

/// 把桥垫片写进 html 本身。
///
/// 内核原本只在 `onPageFinished` 里注入——那是**页面脚本已经跑完**之后，
/// 于是「页面一加载就 `antiSIT.call(...)`」这种写法必然失败，作者只能轮询等垫片。
/// 压缩包拓展的 html 是我们自己读出来交给内核的，顺手塞进去就行：插在 `<head>` 之后
/// （没有 `<head>` 就插在 `<!doctype>` 之后，都没有才放最前面——放 doctype 前面会把
/// 文档推进怪异模式）。
///
/// 网址形态没法这么干（页面不归我们管），仍然靠加载完成后注入。
String injectBridgeShim(String html, String shim) {
  if (shim.trim().isEmpty) return html;
  final script = '<script>$shim</script>';
  final head = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(html);
  if (head != null) return html.replaceRange(head.end, head.end, script);
  final doctype = RegExp(r'<!doctype[^>]*>', caseSensitive: false).firstMatch(html);
  if (doctype != null) return html.replaceRange(doctype.end, doctype.end, script);
  return '$script$html';
}
