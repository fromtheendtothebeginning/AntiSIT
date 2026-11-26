import 'package:campus_core/campus_core.dart';

import 'extension_item.dart';

/// 拼出拓展页 HTML：垫片 → AntiUI → Cordis 运行时 → 引导脚本，按此顺序注入。
String cordisPageHtml({
  required ExtensionItem item,
  required String runtime,
  required String uiCss,
  required String uiJs,
  required String bootstrap,
  required bool allowNetwork,
}) {
    final csp = allowNetwork
        ? "default-src 'none'; script-src 'unsafe-inline' blob:; style-src 'unsafe-inline'; "
            "img-src data: https:; font-src data: https:; media-src https:; "
            "connect-src https:; form-action 'none'; base-uri 'none'"
        : "default-src 'none'; script-src 'unsafe-inline' blob:; style-src 'unsafe-inline'; "
            "img-src data:; font-src data:; connect-src 'none'; "
            "form-action 'none'; base-uri 'none'";
    String safeScript(String s) => s.replaceAll('</script', r'<\/script');
    String safeStyle(String s) => s.replaceAll('</style', r'<\/style');
    return '''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta http-equiv="Content-Security-Policy" content="$csp">
<style>
html,body{margin:0;padding:0;min-height:100%;}
body{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;}
#root{min-height:100vh;box-sizing:border-box;}
#boot{padding:24px;color:#888;font-size:13px;}
.antisit-error{white-space:pre-wrap;word-break:break-word;margin:0;padding:16px;
  background:#2b1111;color:#ffb4b4;font:12px/1.6 ui-monospace,Consolas,monospace;}
</style>
<style>${safeStyle(uiCss)}</style>
</head>
<body>
<div id="root"></div>
<div id="boot">正在启动「${_escapeHtml(item.name)}」…</div>
<script>${safeScript(kWebViewBridgeShim)}</script>
<script>${safeScript(uiJs)}</script>
<script>${safeScript(runtime)}</script>
<script>${safeScript(bootstrap)}</script>
</body>
</html>''';
}

/// 转义 HTML 文本节点。
String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
