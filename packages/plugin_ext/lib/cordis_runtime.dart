import 'package:flutter/services.dart';

import 'cordis_bootstrap.dart';
import 'cordis_page_html.dart';
import 'extension_item.dart';

/// 一条 Cordis 拓展交给 WebView 的页面内容。
class CordisPage {
  const CordisPage({required this.html, required this.mainJs});

  final String html;
  final String mainJs;
}

/// Cordis 拓展运行时：把运行时 bundle、`antiSIT` 垫片、AntiUI 组件和拓展自己的
/// `main.js` 拼成一份自包含页面；注入顺序固定为垫片 → AntiUI → Cordis → 引导脚本。
class CordisRuntime {
  CordisRuntime._();

  static const String _assetKey = 'packages/plugin_ext/assets/cordis.min.js';
  static const String _uiCssKey = 'packages/plugin_ext/assets/anti_ui.css';
  static const String _uiJsKey = 'packages/plugin_ext/assets/anti_ui.js';

  static String? _runtime;
  static String? _uiCss;
  static String? _uiJs;

  /// 读一次 Cordis bundle（约 31 KB），之后走内存缓存。
  static Future<String> loadRuntime() async {
    final cached = _runtime;
    if (cached != null) return cached;
    final text = await rootBundle.loadString(_assetKey);
    _runtime = text;
    return text;
  }

  /// AntiUI 组件（CSS + JS）：每个拓展页都注入，作者不用自己带一套样式。
  static Future<({String css, String js})> loadUiKit() async {
    final css = _uiCss ??= await rootBundle.loadString(_uiCssKey);
    final js = _uiJs ??= await rootBundle.loadString(_uiJsKey);
    return (css: css, js: js);
  }

  /// 生成页面；[allowNetwork] 为 false 时用 CSP 掐掉 fetch / 外链图片。
  static Future<CordisPage> buildPage({
    required ExtensionItem item,
    required String mainJs,
    String css = '',
    required bool allowNetwork,
    required String appVersion,
  }) async {
    final runtime = await loadRuntime();
    final ui = await loadUiKit();
    final html = cordisPageHtml(
      item: item,
      runtime: runtime,
      uiCss: ui.css,
      uiJs: ui.js,
      bootstrap: buildCordisBootstrap(
        item: item,
        mainJs: mainJs,
        css: css,
        appVersion: appVersion,
      ),
      allowNetwork: allowNetwork,
    );
    return CordisPage(html: html, mainJs: mainJs);
  }
}
