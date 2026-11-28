import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:campus_core/campus_core.dart';

import 'cordis_bundle.dart';
import 'ext_bridge_ai.dart';
import 'ext_bridge_args.dart';
import 'ext_bridge_consent.dart';
import 'ext_bridge_notifications.dart';
import 'ext_bridge_theme.dart';
import 'ext_bridge_workshop.dart';
import 'ext_files.dart';
import 'ext_icon.dart';
import 'ext_net.dart';
import 'ext_permissions.dart';
import 'ext_secrets.dart';
import 'ext_voice.dart';
import 'extension_item.dart';
import 'extension_store.dart';
import 'workshop/workshop_store.dart';

/// 拓展网页能用的接口（方法表见 `docs/extensions.md`，网页侧统一 `antiSIT.call(...)`）。
///
/// 每个拓展一个实例：绑定自己的 [extId]（数据互相隔离）与打开网页那个 [context]。
/// 未知方法一律报错回网页；用户数据（学号、课表、成绩）**不在**这套接口里。
class ExtBridge extends WebBridge {
  ExtBridge({
    required this.extId,
    required this.context,
    this.item,
    ExtensionStore? store,
    WorkshopStore? workshop,
  })  : store = store ?? ExtensionStore.I,
        workshop = workshop ?? WorkshopStore();

  /// 内置「拓展工坊」的固定 id：`workshop.*` 只给它用。
  static const String workshopExtId = 'builtin.workshop';

  final String extId;
  final BuildContext context;

  /// 这条拓展（权限门按它判断）。传 null / 非市场来源 = 全量放行。
  final ExtensionItem? item;
  final ExtensionStore store;

  /// 工坊草稿工作区（只有 [workshopExtId] 能碰）。
  final WorkshopStore workshop;

  bool get _isWorkshop => extId == workshopExtId;

  /// 内核 → 网页的下行通道（流式 AI 增量、主题切换用）；页面关掉后为 null。
  WebBridgeEventSink? _events;

  /// 最近一次推给网页的主题 JSON：色板对象变了但实际值没变时不再发。
  String _lastThemeJson = '';
  bool _themeEmitScheduled = false;

  /// 网页页面栈深度变化时通知内核（系统返回键先回退栈内页面）。
  void Function(bool canGoBack)? _backGuard;

  late final ExtNotificationChannel _notify =
      ExtNotificationChannel(context: context, extId: extId, item: item);
  late final ExtPermissionChannel _permissions =
      ExtPermissionChannel(context: context, extId: extId, item: item);
  late final ExtAiChannel _ai = ExtAiChannel(events: () => _events);
  late final ExtVoiceChannel _voice = ExtVoiceChannel(events: () => _events);
  late final WorkshopChannel _workshop =
      WorkshopChannel(store: store, workshop: workshop, context: context);

  @override
  void attachEventSink(WebBridgeEventSink? sink) {
    _events = sink;
    SemColors.palette.removeListener(_onPaletteChanged);
    if (sink == null) {
      // 页面关掉：把 MCP 的 HTTP 连接也关掉，别让 socket 挂在那儿
      _workshop.closeClients();
      return;
    }
    // 页面启动时自己会取一次 theme；这里只记下基准，避免立刻重复推一遍
    _lastThemeJson = jsonEncode(extensionThemeJson());
    SemColors.palette.addListener(_onPaletteChanged);
  }

  /// 主题 / 夜间模式切换：把完整色板推给网页（AntiUI 的 CSS 变量跟着刷新）。
  /// 合并到微任务里，拖动外观滑块时不会一帧推好几次。
  void _onPaletteChanged() {
    if (_events == null || _themeEmitScheduled) return;
    _themeEmitScheduled = true;
    scheduleMicrotask(() {
      _themeEmitScheduled = false;
      final sink = _events;
      if (sink == null) return;
      final theme = extensionThemeJson();
      final json = jsonEncode(theme);
      if (json == _lastThemeJson) return;
      _lastThemeJson = json;
      sink.emit('theme.change', theme);
    });
  }

  @override
  void attachBackGuard(void Function(bool canGoBack)? guard) {
    _backGuard = guard;
  }

  @override
  Future<Object?> call(String method, Object? args) async {
    _checkPermission(method);
    if (method.startsWith('workshop.')) {
      if (!_isWorkshop) {
        throw ArgumentError('workshop.* 只允许内置「拓展工坊」调用');
      }
      // 预览要用本桥接再开一个页面，留在桥内（避免反向依赖）。
      if (method == 'workshop.preview') return _workshopPreview(args);
      // MCP 的凭据（请求头）只在这台设备上，不经过拓展页
      if (method.startsWith('mcp.')) return _workshop.call(method, args);
      return _workshop.call(method, args);
    }
    switch (method) {
      case 'theme':
        return extensionThemeJson();
      case 'toast':
        _toast(args);
        return true;
      case 'close':
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
        return true;
      case 'card.setName':
        return _setCard(args, field: 'name');
      case 'card.setDesc':
        return _setCard(args, field: 'desc');
      case 'card.setIcon':
        return _setCard(args, field: 'icon');
      case 'ui.backDepth':
        return _backDepth(args);
      case 'notify.show':
        return _notify.show(args);
      case 'notify.schedule':
        return _notify.schedule(args);
      case 'notify.cancel':
        return _notify.cancel(args);
      case 'notify.cancelAll':
        return _notify.cancelAll();
      // 运行时授权：拓展可以显式申请 / 查询（弹窗通知、剪贴板、后台、某域名）
      case 'permissions.request':
        return _permissions.request(args);
      case 'permissions.status':
        return _permissions.status(args);
      case 'storage.get':
        return store.dataGet(extId, extArgKey(args));
      case 'storage.set':
        if (args is! Map) throw ArgumentError('storage.set 要带 {key, value}');
        await store.dataSet(extId, extArgKey(args), args['value']);
        return true;
      case 'storage.remove':
        await store.dataRemove(extId, extArgKey(args));
        return true;
      // 加密凭据（Keystore）：Cookie / Token 这类值不要放明文的 storage
      case 'secrets.get':
        return ExtSecrets.get(extId, extSecretKey(args));
      case 'secrets.set':
        if (args is! Map) throw ArgumentError('secrets.set 要带 {key, value}');
        await ExtSecrets.set(extId, extSecretKey(args), '${args['value'] ?? ''}');
        return true;
      case 'secrets.remove':
        await ExtSecrets.remove(extId, extSecretKey(args));
        return true;
      // 原生 HTTPS 代理：不受 CORS 限制，可带 Cookie / Authorization 头
      case 'net.request':
        if (args is! Map) throw ArgumentError('net.request 要带 {url}');
        return ExtNetService.I.request(
          Map<String, Object?>.from(args),
          onHost: (host) => _ensureConsent('net.host:$host'),
        );
      // 校内明文 http：教学站点多是 http://10.x / 210.x，默认通道一律拒
      case 'net.campus':
        if (args is! Map) throw ArgumentError('net.campus 要带 {url}');
        final campusArgs = Map<String, Object?>.from(args);
        // 拓展不填 proxy 时，服务器模式自动用 App 已连上的校园隧道
        if ('${campusArgs['proxy'] ?? ''}'.trim().isEmpty) {
          final proxy = await campusProxyUrl();
          if (proxy.isNotEmpty) campusArgs['proxy'] = proxy;
        }
        return ExtNetService.I.campusRequest(
          campusArgs,
          onHost: (host) => _ensureConsent('net.host:$host'),
        );
      // 剪贴板：读要逐次授权，写只要求静态 clipboard 权限
      case 'clipboard.read':
        await _ensureConsent('clipboard.read');
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        return data?.text ?? '';
      case 'clipboard.write':
        final text = args is Map ? '${args['text'] ?? ''}' : '';
        await Clipboard.setData(ClipboardData(text: text));
        return true;
      // 文件：只通过系统选择器拿 / 存用户明确选中的文件，不暴露任意路径
      case 'files.pick':
        return ExtFilesService.I.pick(args);
      case 'files.save':
        return ExtFilesService.I.save(args);
      // 通用登录页：用户可见地登录，只返回声明域名的 Cookie
      case 'login.open':
        return loginOpen(context: context, extId: extId, item: item, args: args);
      // 退出登录：清掉 WebView CookieStore 里这些域的 Cookie
      case 'login.clear':
        return loginClear(context: context, extId: extId, item: item, args: args);
      // 后台保活：前台服务 + 常驻通知（插件页自己的定时器继续跑）
      case 'background.keepAlive':
        return backgroundKeepAlive(
            context: context, extId: extId, item: item, args: args);
      case 'ai.chat':
        return _ai.chat(args);
      case 'ai.chatTools':
        return _ai.chatTools(args);
      case 'ai.chatToolsStream':
        return _ai.chatToolsStream(args);
      case 'ai.models':
        return _ai.models(args);
      case 'voice.start':
        return _voice.start(args);
      case 'voice.stop':
        return _voice.stop(args);
      case 'voice.cancel':
        return _voice.cancel(args);
      case 'voice.available':
        return _voice.available(args);
      case 'ai.current':
        return _ai.current(args);
      case 'ai.setModel':
        // 换模型是改用户全局配置的副作用操作：只允许内置「拓展工坊」调。
        if (!_isWorkshop) {
          throw ArgumentError('ai.setModel 只允许内置「拓展工坊」调用');
        }
        return _ai.setModel(args);
      default:
        throw ArgumentError('未知接口：$method');
    }
  }

  /// 权限门：**别人写的包**按清单里声明的权限放行，没声明就报错回网页。
  ///
  /// 生效来源：市场装的（[ExtensionItem.fromMarket]）、扫码安装 / 导入压缩包这类
  /// 「别人给的包」（[ExtensionItem.permissionsEnforced]）。只有用户自己手动填网址
  /// 加的远程书签仍全量放行（内容是他自己选的，且没有可读的清单可声明）。
  /// 早先这里只看 `fromMarket`，于是扫码装的拓展权限门完全失效——安装弹窗列的
  /// 权限一条都没执行，比不列更误导。
  void _checkPermission(String method) {
    final it = item;
    if (it == null || !it.gated) return;
    final need = kMethodPermissions[method];
    if (need == null) return;
    if (!it.permissions.contains(need)) {
      throw ArgumentError('这条拓展没有声明「${kPermissionLabels[need] ?? need}」权限（$need），接口已拒');
    }
  }

  Future<void> _ensureConsent(String capability) => ensureExtConsent(
        context: context,
        extId: extId,
        item: item,
        capability: capability,
      );

  /// 页面栈深度同步：网页执行 `ctx.ui.push` / `pop` 后告诉我们还剩几层。
  Object? _backDepth(Object? args) {
    final raw = args is Map ? args['depth'] : null;
    final depth = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
    _backGuard?.call(depth > 0);
    return true;
  }

  /// 改自己卡片上的一个字段（名称 / 简介 / 图标），改完落盘，回到列表即可见。
  /// 校验不过直接报错，不静默截断。
  Future<Object?> _setCard(Object? args, {required String field}) async {
    if (args is! Map) throw ArgumentError('card.set$field 要带 {text}');
    final text = '${args['text'] ?? ''}'.trim();
    if (field == 'name') {
      if (text.isEmpty) throw ArgumentError('名称不能为空');
      if (text.length > ExtensionItem.nameMaxLength) {
        throw ArgumentError('名称最多 ${ExtensionItem.nameMaxLength} 个字');
      }
    } else if (field == 'icon') {
      // 图片网址 / 镂空图标不受「几个字」的限制，这里只给个长度上限
      final isLine = text.startsWith('line:');
      if (isLine && !ExtIcon.lineIcons.containsKey(text.substring(5))) {
        throw ArgumentError('镂空图标名不认识：${text.substring(5)}（可用：'
            '${ExtIcon.lineIcons.keys.join(' / ')}）');
      }
      if (text.length > (isHttpUrl(text) || isLine ? 300 : ExtensionItem.iconTextMaxLength)) {
        throw ArgumentError(isHttpUrl(text) || isLine
            ? '图标值过长'
            : '图标最多 ${ExtensionItem.iconTextMaxLength} 个字（要用图片就填 http/https 网址）');
      }
    } else if (text.length > ExtensionItem.descMaxLength) {
      throw ArgumentError('简介最多 ${ExtensionItem.descMaxLength} 个字');
    }
    final ok = await store.setCard(extId,
        name: field == 'name' ? text : null,
        desc: field == 'desc' ? text : null,
        icon: field == 'icon' ? text : null);
    if (!ok) throw ArgumentError('这条拓展不在清单里，改不了卡片');
    return true;
  }

  /// 预览草稿：用本桥接给草稿开一个临时页面。
  Future<Object?> _workshopPreview(Object? args) async {
    final a = args is Map ? Map<String, Object?>.from(args) : <String, Object?>{};
    final draft = await workshop.load(extArgString(a, 'draftId'));
    if (draft == null) throw ArgumentError('拓展不存在或 ext.json 已损坏');
    final kernel =
        PluginRegistry.I.capability<WebViewCapability>(PluginIds.webview);
    if (kernel == null || !kernel.available) {
      throw ArgumentError('WebView 内核没启用，无法预览');
    }
    final item = workshop.itemOf(draft);
    final page = await CordisBundleLoader.load(
      item,
      appVersion: await ExtensionItem.appVersionLoader(),
    );
    if (context.mounted) {
      unawaited(kernel.openPage(
        context,
        html: page.html,
        title: '预览 · ${draft.manifest.name}',
        bridge: ExtBridge(extId: draft.id, context: context, item: item),
      ));
    }
    return {'ok': true};
  }

  void _toast(Object? args) {
    if (!context.mounted) return;
    final text = args is Map ? '${args['text'] ?? ''}' : '$args';
    if (text.trim().isEmpty) return;
    // 先收掉上一条：连点几下不会把一串提示排队堆在底部，盖住网页自己的输入区
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(text, style: const TextStyle(fontSize: 13)),
          behavior: SnackBarBehavior.floating));
  }
}
