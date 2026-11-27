import 'dart:async';
import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';

import 'cordis_bundle.dart';
import 'ext_bridge.dart';
import 'ext_bridge_consent.dart';
import 'extension_item.dart';
import 'extension_store.dart';

/// 打开一条拓展：把入口内容拿给 WebView 内核，带上这条拓展自己的接口通道。
///
/// 「拓展」页与「插件市场」页共用；平台不支持 / 内核没开 / App 版本不够都会走
/// [onMessage] 说一句（调用方决定是 snackbar 还是别的）。
Future<void> openExtension(
  BuildContext context,
  ExtensionItem e, {
  void Function(String)? onMessage,
}) async {
  void say(String msg) => onMessage?.call(msg);

  // App 版本门放在最前：导入的 JSON 没有市场那道安装门，版本比较又便宜
  if (e.needsNewerApp(await ExtensionItem.appVersionLoader())) {
    say('「${e.name}」需要 App ≥${e.minAppVersion}，请先升级 App 再打开');
    return;
  }

  // 旧版 html 压缩包：运行时已切到 Cordis，不能再把任意 html 当拓展跑
  if (e.runtime == ExtensionItem.runtimeLegacy) {
    say('「${e.name}」是旧版网页拓展，当前运行时已停止支持；请让作者用 Cordis 重新打包，或到「拓展工坊」重建');
    return;
  }

  final kernel = PluginRegistry.I.capability<WebViewCapability>(
    PluginIds.webview,
  );
  if (kernel == null) {
    say('WebView 内核没启用：到「插件管理」里打开它');
    return;
  }
  if (!kernel.available) {
    say('当前平台不支持网页拓展（内核只覆盖 Android / iOS）');
    return;
  }
  // Cordis 拓展：读 ext.json + main.js，拼一份自包含页面交给内核
  String? html;
  if (e.isCordis) {
    try {
      final page = await CordisBundleLoader.load(
        e,
        appVersion: await ExtensionItem.appVersionLoader(),
      );
      html = page.html;
    } on FormatException catch (err) {
      say('「${e.name}」加载失败：${err.message}');
      return;
    } catch (err) {
      say('「${e.name}」加载失败：$err');
      return;
    }
  }
  // 版本门 / 读文件都 await 过了：页面可能已经不在树上
  if (!context.mounted) return;
  // 校内网页（融合门户这类只有内网能到的站点）：服务器模式下走校园隧道，
  // 与大物实验提醒同一个出口；直连模式 / 演示直接加载（那时手机本来就在校内网里）。
  final intranet = await wantsCampusPage(e);
  final proxy = await campusProxyForExtension(e);
  if (!context.mounted) return;
  await kernel.openPage(
    context,
    url: e.isCordis ? null : e.url,
    html: html,
    title: e.name,
    bridge: ExtBridge(extId: e.id, context: context, item: e),
    proxy: proxy,
  );
  if (proxy.isEmpty && intranet && !AppState.I.direct) {
    say('「${e.name}」只有校内网能打开：请先到「我的 → 校园服务」连接校园网，或切到直连模式');
  }
}

/// 这条拓展是不是「只有校内网能到」的网页。两个判据：
///
/// 1. 市场清单里声明了 `campus_net`（作者自己标明「要连校园网」）；
/// 2. 网址的域名解析到 RFC1918 内网地址（融合门户 `portal.sit.edu.cn` 就是
///    172.24.x）——老条目没声明也不影响，不然已经装着的用户得卸载重装才生效。
bool declaresCampusNet(ExtensionItem e) =>
    !e.bundled &&
    e.runtime != ExtensionItem.runtimeCordis &&
    e.permissions.contains('campus_net');

/// 域名解析入口（测试里换成固定结果，免得真查 DNS）。
@visibleForTesting
Future<List<InternetAddress>> Function(String host) campusHostLookup = (host) =>
    InternetAddress.lookup(host).timeout(const Duration(seconds: 3));

Future<bool> wantsCampusPage(ExtensionItem e) async {
  if (e.bundled || e.runtime == ExtensionItem.runtimeCordis) return false;
  if (declaresCampusNet(e)) return true;
  final host = Uri.tryParse(e.url.trim())?.host ?? '';
  if (host.isEmpty) return false;
  try {
    final addrs = await campusHostLookup(host);
    return addrs.any(isPrivateAddress);
  } catch (_) {
    // 解析不出来就按公网处理：真打不开时网页自己会给加载失败，不该拦着。
    return false;
  }
}

/// RFC1918 / 典型的校内网段：10/8、172.16/12、192.168/16（IPv6 的 ULA 也算）。
@visibleForTesting
bool isPrivateAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (bytes.length == 16) {
    // ULA fc00::/7
    return (bytes[0] & 0xfe) == 0xfc;
  }
  if (bytes.length != 4) return false;
  final a = bytes[0], b = bytes[1];
  if (a == 10) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 192 && b == 168) return true;
  return false;
}

/// 取校园隧道网页代理的探测入口（测试里换成固定值）。
@visibleForTesting
Future<String> Function() campusProxyProbe = campusProxyUrl;

/// 探测之间的间隔（测试里改成零，免得用例真的等 2 秒）。
@visibleForTesting
Duration campusProxyRetryDelay = const Duration(seconds: 2);

/// 测试收尾：把探测入口与间隔还原成真实实现。
@visibleForTesting
void resetCampusProxyProbe() {
  campusProxyProbe = campusProxyUrl;
  campusProxyRetryDelay = const Duration(seconds: 2);
  campusHostLookup = (host) =>
      InternetAddress.lookup(host).timeout(const Duration(seconds: 3));
}

/// 取校园隧道网页代理（`http://host:port`）。服务器侧的隧道是**按需**建的：
/// 只有隧道请求收到 202 才开始建，建好之前 `/status` 里没有 `http_port`。
/// 所以探不到就先发一个轻量隧道请求把流程推起来，再按 2 秒一轮等最多 6 秒
/// （用户可能刚点开、隧道还在建；等太久的话页面迟迟不出现，比直连失败更难受）。
/// 一直拿不到就按直连打开，由调用方补一句提示。
Future<String> campusProxyForExtension(ExtensionItem e) async {
  // 没填服务器地址 / 直连模式：等再久也不会有隧道，直接直连。
  if (AppState.I.direct || AppState.I.serverUrl.isEmpty) return '';
  if (!await wantsCampusPage(e)) return '';
  var warmupStarted = false;
  for (var attempt = 0; attempt < 3; attempt++) {
    final proxy = await campusProxyProbe();
    if (proxy.isNotEmpty) return proxy;
    if (!warmupStarted) {
      warmupStarted = true;
      // 顺手推一下建隧道：隧道类接口收到 202 才会开始连校园网。
      unawaited(
        ApiClient.I.score().catchError((Object _) => <String, dynamic>{}),
      );
      continue;
    }
    await Future<void>.delayed(campusProxyRetryDelay);
  }
  return '';
}

/// 删除 / 卸载一条拓展前跟用户确认：说清会连带清掉什么。
/// 确认返回 true。内置拓展不能删（返回 false，调用方自己别显示入口）。
Future<bool> confirmRemoveExtension(
  BuildContext context,
  ExtensionItem e,
) async {
  if (ExtensionStore.I.isBuiltin(e.id)) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('删除「${e.name}」？'),
      content: Text(
        e.bundled
            ? '会连同装进来的文件一起删掉，它的本地存储也会清掉。'
            : '只是从列表里去掉，网页本身不受影响；它的本地存储也会一起清掉。',
        style: const TextStyle(fontSize: 13, height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
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
