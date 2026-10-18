import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'bundle_import.dart';
import 'ext_bridge.dart';
import 'extension_item.dart';
import 'extension_store.dart';

/// 打开一条拓展：把入口内容拿给 WebView 内核，带上这条拓展自己的接口通道。
///
/// 「拓展」页与「插件市场」页共用（市场卡片上的「打开」跟列表里点卡片是同一件事）。
/// 平台不支持 / 内核没开 → 用 [onMessage] 说一句（调用方决定是 snackbar 还是别的）。
Future<void> openExtension(
  BuildContext context,
  ExtensionItem e, {
  void Function(String)? onMessage,
}) async {
  void say(String msg) => onMessage?.call(msg);

  final kernel = PluginRegistry.I.capability<WebViewCapability>(PluginIds.webview);
  if (kernel == null) {
    say('WebView 内核没启用：到「插件管理」里打开它');
    return;
  }
  if (!kernel.available) {
    say('当前平台不支持网页拓展（内核只覆盖 Android / iOS）');
    return;
  }
  // 压缩包导入的：把入口页读出来、同目录 css/js 内联成自包含页面再交给内核
  String? html;
  if (e.bundled) {
    try {
      html = bundlePageHtml(e.url);
    } catch (_) {
      say('这个压缩包的内容读不到了（可能被清理过），重新装一次即可');
      return;
    }
    // 市场装的拓展默认禁网（声明 network 才放开）：审核过的页面不该在运行时
    // 再去拉别处的脚本。用户自己导入的压缩包不上这条——跟权限门同一条边界。
    if (e.fromMarket) {
      html = applyExtensionCsp(html, allowNetwork: e.permissions.contains('network'));
    }
  }
  await kernel.openPage(
    context,
    url: e.bundled ? null : e.url,
    html: html,
    title: e.name,
    bridge: ExtBridge(extId: e.id, context: context, item: e),
  );
}

/// 删除 / 卸载一条拓展前跟用户确认：说清会连带清掉什么。
/// 确认返回 true。内置拓展不能删（返回 false，调用方自己别显示入口）。
Future<bool> confirmRemoveExtension(BuildContext context, ExtensionItem e) async {
  if (ExtensionStore.I.isBuiltin(e.id)) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('删除「${e.name}」？'),
      content: Text(
          e.bundled
              ? '会连同装进来的文件一起删掉，它的本地存储也会清掉。'
              : '只是从列表里去掉，网页本身不受影响；它的本地存储也会一起清掉。',
          style: const TextStyle(fontSize: 13, height: 1.6)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: SemColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return ok == true;
}
