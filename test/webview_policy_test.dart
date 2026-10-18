import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_webview/plugin_webview.dart';

/// 内核「纯逻辑」那部分的验收（见 `webview_policy.dart`）：
///
/// * **导航判定**：内联 html（压缩包拓展）里的 http(s) 外链要拦下来交给系统浏览器
///   ——否则页面跳走以后，内核每次 onPageFinished 都会把 `antiSIT` 垫片重新注入，
///   等于把「网页 ↔ App 通道」送给外面那个站点；网址形态（用户自己填的站点）不拦；
/// * **垫片预注入**：内联 html 的垫片写进页面本身，网页第一个同步脚本就能用 `antiSIT`
///   （只靠 onPageFinished 注入是「页面脚本已经跑完」之后，晚一步）。
void main() {
  group('主框架导航判定', () {
    NavAction nav(String url, {bool isMainFrame = true, required bool inline}) =>
        decideMainFrameNavigation(url, isMainFrame: isMainFrame, fromInlineHtml: inline);

    test('内联页点 http(s) 外链 → 交系统浏览器（不带着通道跳走）', () {
      expect(nav('https://example.com/a', inline: true), NavAction.openExternal);
      expect(nav('http://example.com', inline: true), NavAction.openExternal);
    });

    test('内联页自己的本地方案照走', () {
      for (final url in [
        'about:blank',
        'data:text/html,hi',
        'blob:https://x/y',
        'javascript:void(0)',
        '#anchor',
      ]) {
        expect(nav(url, inline: true), NavAction.allow, reason: url);
      }
    });

    test('内联页里的危险方案：拦下且不打开', () {
      expect(nav('file:///etc/passwd', inline: true), NavAction.block);
      expect(nav('intent://scan#Intent;scheme=zxing;end', inline: true), NavAction.block);
      expect(nav('content://media/1', inline: true), NavAction.block);
    });

    test('网址形态就是普通浏览：不拦', () {
      expect(nav('https://example.com/a', inline: false), NavAction.allow);
      expect(nav('https://other.com/login?next=x', inline: false), NavAction.allow);
    });

    test('子框架（iframe）一律放行——那是网页自己的排版', () {
      expect(
          nav('https://cdn.example.com/w.html', isMainFrame: false, inline: true),
          NavAction.allow);
    });
  });

  group('垫片预注入', () {
    const shim = 'window.antiSIT = 1;';

    test('有 head 就插在 head 之后（正文之前、页面自己的脚本之前）', () {
      final html = '<!doctype html><html><head><meta charset="utf-8"></head>'
          '<body>hi</body></html>';
      final out = injectBridgeShim(html, shim);
      expect(out, contains('<head><script>window.antiSIT = 1;</script><meta charset="utf-8">'));
      expect(out.indexOf('<script>'), lessThan(out.indexOf('<body>')));
      expect(out.startsWith('<!doctype html>'), isTrue, reason: '别把 doctype 顶掉（怪异模式）');
    });

    test('没有 head：插在 doctype 之后（仍在正文之前）', () {
      final out = injectBridgeShim('<!doctype html><body>x</body>', shim);
      expect(out, '<!doctype html><script>window.antiSIT = 1;</script><body>x</body>');
    });

    test('什么都没有：放最前面', () {
      expect(injectBridgeShim('<h1>x</h1>', shim), '<script>window.antiSIT = 1;</script><h1>x</h1>');
    });

    test('空垫片原样返回（没桥时不该动页面）', () {
      expect(injectBridgeShim('<h1>x</h1>', '  '), '<h1>x</h1>');
    });
  });
}
