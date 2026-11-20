import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:campus_core/campus_core.dart';

import 'cordis_bundle.dart';
import 'ext_background.dart';
import 'ext_consent.dart';
import 'ext_cookie_bridge.dart';
import 'ext_files.dart';
import 'ext_icon.dart';
import 'ext_login_page.dart';
import 'ext_net.dart';
import 'ext_secrets.dart';
import 'ext_notification.dart';
import 'ext_permissions.dart';
import 'extension_item.dart';
import 'extension_store.dart';
import 'publish/publish_page.dart';
import 'workshop/workshop_store.dart';

/// 拓展网页能用的接口（方法表见 `docs/extensions.md`，网页侧统一 `antiSIT.call(...)`）：
///
/// | 方法 | 参数 | 返回 |
/// |---|---|---|
/// | `theme` | — | 当前配色的完整令牌（`bg` / `card` / `menuBg` / `inputFill` / `overlay` / `gold` / `radiusCard` / `wells` …）；主题或夜间模式变化时通过 `antiSIT.on('theme.change')` 再推一次 |
/// | `toast` | `{text}` | 弹一条 App 风格的提示 |
/// | `close` | — | 关掉当前网页（回拓展列表） |
/// | `card.setName` | `{text}` | 换卡片上的名称（≤ 20 字；id 不变） |
/// | `card.setDesc` | `{text}` | 换卡片上的简介（≤ 60 字；空串 = 不显示简介） |
/// | `card.setIcon` | `{text}` | 换卡片上的图标（`line:<name>` 镂空图标、图片网址，或 ≤ 4 字的文字 / emoji；空串 = 用网站 favicon） |
/// | `ui.backDepth` | `{depth}` | 网页页面栈深度变化；内核据此决定系统返回先退栈还是关页 |
/// | `notify.show` | `{title, body?, key?, popup?}` | 立即发一条本地通知（同 key 覆盖）；`popup: true` 走高优先级「弹窗」渠道（屏幕横幅），首次会弹运行时确认；首次调用申请系统通知权限 |
/// | `notify.schedule` | `{key, title, body?, at}` | 定时通知；`at` 为 ISO 8601 或毫秒时间戳（未来） |
/// | `notify.cancel` | `{key}` | 撤掉一条 / `notify.cancelAll` 撤掉这条拓展的全部通知 |
/// | `permissions.request` | `{name, host?}` | 显式申请一项运行时授权（`notification.popup` / `clipboard.read` / `background.keepalive` / `net.host` / `login.open`）；返回 `{name, granted}` |
/// | `permissions.status` | `{name, host?}` | 查已记住的状态：`{name, granted}`；`granted` 为 null 表示还没问过 |
/// | `storage.get` | `{key}` | 该拓展自己存的任意 JSON；没有则 null |
/// | `storage.set` | `{key, value}` | true |
/// | `storage.remove` | `{key}` | true |
/// | `secrets.get` | `{key}` | 读本拓展的加密凭据（Keystore / Keychain）；没有则 null |
/// | `secrets.set` | `{key, value}` | 写加密凭据；值只按拓展 id 隔离 |
/// | `secrets.remove` | `{key}` | 删除一条加密凭据 |
/// | `net.request` | `{method?, url, headers?, body?, bodyBase64?}` | 原生 HTTPS 代理（不受 CORS 限制，可带 Cookie 头）；返回 `{status, url, headers, setCookies, text, truncated, bytes}`。只允许 https，拒绝内网地址；每个新域名（含重定向）首次访问会弹窗确认 |
/// | `clipboard.read` | — | 读剪贴板文本；首次 / 未记住时弹窗确认（需 `clipboard` 权限） |
/// | `clipboard.write` | `{text}` | 写剪贴板（需 `clipboard` 权限） |
/// | `files.pick` | `{accept?, multiple?, encoding?}` | 打开系统文件选择器，返回 `{files: [{name, size, mime, text?/base64?}]}`；单文件 ≤ 8 MB，一次 ≤ 10 个（需 `files` 权限） |
/// | `files.save` | `{name, text?/base64?, mime?}` | 打开系统「保存到」选择器写文件；用户取消返回 false（需 `files` 权限） |
/// | `login.open` | `{url, cookieUrls, title?, successUrlPrefix?, successCookie?, userAgent?}` | 打开可见登录页；返回 `{cookies: {域名: cookie}, cookieHeader}`。`cookieUrls` 必须与登录地址同站；需 `login` 权限，打开前会弹窗确认 |
/// | `login.clear` | `{cookieUrls}` | 退出登录：删掉这些域在系统 CookieStore 里的 Cookie（含父域与常见子路径）；返回 `{ok}`，`ok=false` 表示没清干净；需 `login` 权限 |
/// | `ai.chat` | `{prompt, system?, maxTokens?}` | 模型回答文本。提示词由 App 本地转成当前 AI 提供商的请求（Key / 模型不出 App）；没配好 AI 或市场拓展没声明 `ai` 权限都直接报错 |
/// | `ai.chatTools` | `{messages, tools?, maxTokens?}` | 多轮消息 + OpenAI 兼容 function calling；返回 `{text, toolCalls, usedTools, finishReason}`。提供商不支持 tools 时自动降级 |
///
/// 每个拓展一个实例：绑定自己的 [extId]（数据互相隔离）与打开网页那个 [context]
/// （提示条 / 关页要用）。未知方法一律报错回网页，不静默失败——拓展作者调试时
/// 能立刻看见；用户数据（学号、课表、成绩）**不在**这套接口里，别把用户数据
/// 交给一个用户自己填的网址。
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

  /// 完全访问模式：跳过写入 / 删除 / 安装的原生确认（只由工坊自己的开关打开）。
  bool _fullAccess = false;

  @override
  void attachEventSink(WebBridgeEventSink? sink) {
    _events = sink;
    SemColors.palette.removeListener(_onPaletteChanged);
    if (sink == null) return;
    // 页面启动时自己会取一次 theme；这里只记下基准，避免立刻重复推一遍
    _lastThemeJson = jsonEncode(_theme());
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
      final theme = _theme();
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
      return _workshopCall(method, args);
    }
    switch (method) {
      case 'theme':
        return _theme();
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
        return _notifyShow(args);
      case 'notify.schedule':
        return _notifySchedule(args);
      case 'notify.cancel':
        return _notifyCancel(args);
      case 'notify.cancelAll':
        return _notifyCancelAll();
      // 运行时授权：拓展可以显式申请 / 查询（弹窗通知、剪贴板、后台、某域名）
      case 'permissions.request':
        return _permissionsRequest(args);
      case 'permissions.status':
        return _permissionsStatus(args);
      case 'storage.get':
        return store.dataGet(extId, _key(args));
      case 'storage.set':
        if (args is! Map) throw ArgumentError('storage.set 要带 {key, value}');
        await store.dataSet(extId, _key(args), args['value']);
        return true;
      case 'storage.remove':
        await store.dataRemove(extId, _key(args));
        return true;
      // 加密凭据（Keystore）：Cookie / Token 这类值不要放明文的 storage
      case 'secrets.get':
        return ExtSecrets.get(extId, _secretKey(args));
      case 'secrets.set':
        if (args is! Map) throw ArgumentError('secrets.set 要带 {key, value}');
        await ExtSecrets.set(extId, _secretKey(args), '${args['value'] ?? ''}');
        return true;
      case 'secrets.remove':
        await ExtSecrets.remove(extId, _secretKey(args));
        return true;
      // 原生 HTTPS 代理：不受 CORS 限制，可带 Cookie / Authorization 头
      case 'net.request':
        if (args is! Map) throw ArgumentError('net.request 要带 {url}');
        return ExtNetService.I.request(
          Map<String, Object?>.from(args),
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
        return _loginOpen(args);
      // 退出登录：清掉 WebView CookieStore 里这些域的 Cookie（否则「重新登录」会一堆已登录态）
      case 'login.clear':
        return _loginClear(args);
      // 后台保活：前台服务 + 常驻通知（插件页自己的定时器继续跑）
      case 'background.keepAlive':
        return _backgroundKeepAlive(args);
      case 'ai.chat':
        return _aiChat(args);
      case 'ai.chatTools':
        return _aiChatTools(args);
      case 'ai.chatToolsStream':
        return _aiChatToolsStream(args);
      default:
        throw ArgumentError('未知接口：$method');
    }
  }

  /// 权限门：市场装的拓展按清单里声明的权限放行，没声明就报错回网页
  /// （网页侧会 Promise reject，作者一眼看得出是哪条没写）。
  /// 用户自己填网址 / 自己挑压缩包装的拓展全量放行——来源是他自己选的，
  /// 我们没资格替他设限；[item] 为空的老调用同理。
  void _checkPermission(String method) {
    final it = item;
    if (it == null || !it.fromMarket) return;
    final need = kMethodPermissions[method];
    if (need == null) return;
    if (!it.permissions.contains(need)) {
      throw ArgumentError('这条拓展没有声明「${kPermissionLabels[need] ?? need}」权限（$need），接口已拒');
    }
  }

  /// 运行时授权：静态权限之外，剪贴板 / 特定域名这类动作再让用户确认一次。
  /// 用户拒绝时抛错回网页，调用方不应继续。
  Future<void> _ensureConsent(String capability) async {
    final allowed = await ExtConsentService.I.ensure(
      context,
      extId: extId,
      extName: item?.name ?? extId,
      capability: capability,
    );
    if (!allowed) {
      throw ArgumentError('用户没有允许这项操作（$capability）');
    }
  }

  /// 退出登录：把 [cookieUrls] 这些域的 Cookie 从系统 CookieStore 里删掉。
  ///
  /// WebView 共用同一个 CookieStore：用户在登录页登过学习通后，即使用拓展里的
  /// 「清除」删了自己的加密凭据，下次打开登录页仍然是已登录状态（看起来像
  /// 「退不出去」）。这里补一条真正的清理通道，由拓展在「退出账号」时调用。
  ///
  /// 返回 `{ok: bool}`：`ok=false` 表示清完后仍读得到 Cookie（父域 / 子路径没清干净），
  /// 拓展应当如实告诉用户「可能没退干净」，而不是假装成功。
  Future<Object?> _loginClear(Object? args) async {
    if (args is! Map) throw ArgumentError('login.clear 要带 {cookieUrls}');
    if (!ExtCookieBridge.supported) {
      throw ArgumentError('登录页目前只支持 Android');
    }
    final urls = <String>[];
    final raw = args['cookieUrls'];
    if (raw is List) {
      for (final item in raw) {
        final uri = ExtLoginPage.parseHttpsUrl('$item');
        urls.add(uri.toString());
      }
    }
    if (urls.isEmpty) throw ArgumentError('login.clear 要带至少一个 cookieUrls');
    await _ensureConsent('login.open:${Uri.parse(urls.first).host}');
    final ok = await ExtCookieBridge.remove(urls);
    return {'ok': ok};
  }

  /// 打开一个可见的登录页，完成后只返回拓展声明的域名的 Cookie。
  Future<Object?> _loginOpen(Object? args) async {
    if (args is! Map) throw ArgumentError('login.open 要带 {url}');
    if (!ExtCookieBridge.supported) {
      throw ArgumentError('登录页目前只支持 Android');
    }
    final start = ExtLoginPage.parseHttpsUrl('${args['url'] ?? ''}');
    final cookieUrls = <String>[];
    final raw = args['cookieUrls'];
    if (raw is List) {
      for (final item in raw) {
        final uri = ExtLoginPage.parseHttpsUrl('$item');
        if (!ExtLoginPage.sameSite(start.host, uri.host)) {
          throw ArgumentError('cookieUrls 必须与登录地址同站：${uri.host}');
        }
        cookieUrls.add(uri.toString());
      }
    }
    if (cookieUrls.isEmpty) cookieUrls.add(start.toString());

    await _ensureConsent('login.open:${start.host}');
    if (!context.mounted) throw StateError('页面已关闭');
    final result = await Navigator.of(context).push<Map<String, Object?>>(
      MaterialPageRoute(
        builder: (_) => ExtLoginPage(
          title: '${args['title'] ?? '登录'}',
          startUrl: start.toString(),
          cookieUrls: cookieUrls,
          successUrlPrefix: args['successUrlPrefix']?.toString(),
          successCookie: args['successCookie']?.toString(),
          userAgent: args['userAgent']?.toString(),
        ),
      ),
    );
    if (result == null) throw ArgumentError('没有完成登录');
    return result;
  }

  /// 后台保活：开启前先要用户同意；关闭时直接停前台服务。
  Future<Object?> _backgroundKeepAlive(Object? args) async {
    final map = args is Map ? args : const {};
    final enabled = map['enabled'] != false;
    if (!enabled) {
      await ExtBackgroundKeepAlive.stop();
      return false;
    }
    await _ensureConsent('background.keepalive');
    final ok = await ExtBackgroundKeepAlive.start(
      title: '${map['title'] ?? item?.name ?? '拓展'}',
      text: '${map['text'] ?? '正在后台刷新'}',
    );
    return ok;
  }

  /// 页面栈深度同步：网页执行 `ctx.ui.push` / `pop` 后告诉我们还剩几层。
  /// 内核据此把系统返回键先交给网页（`window.__antiSITBack()`），栈空才关整页。
  Object? _backDepth(Object? args) {
    final raw = args is Map ? args['depth'] : null;
    final depth = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
    _backGuard?.call(depth > 0);
    return true;
  }

  // ==================== 通知（notification 权限）====================

  Future<Object?> _notifyShow(Object? args) async {
    final popup = args is Map && args['popup'] == true;
    if (popup) await _ensureConsent('notification.popup');
    await ExtNotificationService.instance.show(
      extId: extId,
      key: _notifyKey(args, required: false),
      title: _notifyTitle(args),
      body: _notifyBody(args),
      popup: popup,
    );
    return true;
  }

  Future<Object?> _notifySchedule(Object? args) async {
    if (args is! Map) throw ArgumentError('notify.schedule 要带 {key, title, at}');
    final popup = args['popup'] == true;
    if (popup) await _ensureConsent('notification.popup');
    await ExtNotificationService.instance.schedule(
      extId: extId,
      key: _notifyKey(args, required: true)!,
      title: _notifyTitle(args),
      body: _notifyBody(args),
      at: _notifyAt(args),
      popup: popup,
    );
    return true;
  }

  Future<Object?> _notifyCancel(Object? args) async {
    await ExtNotificationService.instance
        .cancel(extId: extId, key: _notifyKey(args, required: true)!);
    return true;
  }

  Future<Object?> _notifyCancelAll() async {
    await ExtNotificationService.instance.cancelAll(extId: extId);
    return true;
  }

  static const Set<String> _simpleCapabilities = {
    'notification.popup',
    'clipboard.read',
    'background.keepalive',
  };

  /// 把 `{name, host?}` 解析成内部能力键；只认白名单，避免拓展写任意键。
  static String _capabilityFromArgs(Object? args) {
    if (args is String) return _validateCapability(args.trim());
    if (args is! Map) throw ArgumentError('permissions 要带 {name}');
    final name = '${args['name'] ?? ''}'.trim();
    if (name == 'net.host' || name == 'login.open') {
      final host = '${args['host'] ?? ''}'.trim().toLowerCase();
      if (host.isEmpty || !RegExp(r'^[a-z0-9.-]+$').hasMatch(host)) {
        throw ArgumentError('$name 要带合法 host');
      }
      return '$name:$host';
    }
    return _validateCapability(name);
  }

  static String _validateCapability(String name) {
    if (_simpleCapabilities.contains(name)) return name;
    throw ArgumentError('不认识的能力：$name');
  }

  Future<Object?> _permissionsRequest(Object? args) async {
    final capability = _capabilityFromArgs(args);
    final granted = await ExtConsentService.I.ensure(
      context,
      extId: extId,
      extName: item?.name ?? extId,
      capability: capability,
    );
    return {'name': capability, 'granted': granted};
  }

  Future<Object?> _permissionsStatus(Object? args) async {
    final capability = _capabilityFromArgs(args);
    final grants = await ExtConsentService.I.grants(extId);
    return {'name': capability, 'granted': grants[capability]};
  }

  /// 通知标题：必填，给个 200 字上限（系统通知栏也放不下更多）。
  static String _notifyTitle(Object? args) {
    final title = args is Map ? '${args['title'] ?? ''}'.trim() : '';
    if (title.isEmpty) throw ArgumentError('通知要带 title');
    if (title.length > 200) throw ArgumentError('通知 title 最多 200 字');
    return title;
  }

  /// 通知正文：可空；空串按没有正文处理。
  static String? _notifyBody(Object? args) {
    if (args is! Map) return null;
    final body = '${args['body'] ?? ''}'.trim();
    if (body.length > 1000) throw ArgumentError('通知 body 最多 1000 字');
    return body.isEmpty ? null : body;
  }

  /// 拓展自己给的稳定 key：取消 / 覆盖同一条通知靠它。
  /// [required] 为 false 时可以不传（立即通知用当前时刻生成一个）。
  static String? _notifyKey(Object? args, {required bool required}) {
    final key = args is Map ? '${args['key'] ?? ''}'.trim() : '';
    if (key.isEmpty) {
      if (required) throw ArgumentError('要带 key（取消 / 覆盖同一条通知靠它）');
      return null;
    }
    if (key.length > 100) throw ArgumentError('通知 key 最多 100 字');
    return key;
  }

  /// 定时时刻：ISO 8601 字符串或毫秒时间戳；只接受未来时间。
  static DateTime _notifyAt(Object? args) {
    final raw = args is Map ? args['at'] : null;
    DateTime? at;
    if (raw is num) {
      at = DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    } else if (raw is String && raw.trim().isNotEmpty) {
      at = DateTime.tryParse(raw.trim());
    }
    if (at == null) {
      throw ArgumentError('notify.schedule 要带 at（ISO 8601 时间或毫秒时间戳）');
    }
    if (!at.isAfter(DateTime.now())) throw ArgumentError('at 必须是未来时间');
    return at;
  }

  /// 改自己卡片上的一个字段（名称 / 简介 / 图标），改完落盘，回到列表即可见。
  /// 校验不过直接报错，不静默截断：名称不能空、简介可空（= 不显示）、
  /// 图标可以是 `line:<name>` 镂空图标、图片网址，或几个字以内的文字 / emoji。
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
      if (text.length > (_isUrl(text) || isLine ? 300 : ExtensionItem.iconTextMaxLength)) {
        throw ArgumentError(_isUrl(text) || isLine
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

  static bool _isUrl(String s) => s.startsWith('http://') || s.startsWith('https://');

  /// AI 对话：提示词由 App 本地转成当前 AI 提供商的请求（Key / 模型都留在
  /// App 侧，网页只拿到回答文本）。AI 插件没装 / 被停用 / 没配置都如实报错。
  /// prompt / system 有长度上限：网页传多大的串都照单全收的话，序列化超大
  /// 请求体能把 App 卡死。
  static const int _maxAiTextChars = 32768;

  Future<Object?> _aiChat(Object? args) async {
    if (args is! Map) throw ArgumentError('ai.chat 要带 {prompt}');
    final prompt = '${args['prompt'] ?? ''}'.trim();
    if (prompt.isEmpty) throw ArgumentError('prompt 不能为空');
    if (prompt.length > _maxAiTextChars) {
      throw ArgumentError('prompt 太长（最多 $_maxAiTextChars 字）');
    }
    final system = args['system']?.toString();
    if (system != null && system.length > _maxAiTextChars) {
      throw ArgumentError('system 太长（最多 $_maxAiTextChars 字）');
    }
    final maxRaw = args['maxTokens'];
    final int maxTokens;
    if (maxRaw == null) {
      maxTokens = 1024;
    } else if (maxRaw is num && maxRaw > 0) {
      maxTokens = maxRaw.toInt().clamp(16, 4096).toInt();
    } else {
      throw ArgumentError('maxTokens 要是正数（缺省 1024，收在 16–4096）');
    }
    final ai = PluginRegistry.I.capability<AiCapability>(PluginIds.ai);
    if (ai == null || !ai.available) {
      throw ArgumentError('AI 还没配好：到「我的 → AI 设置」选择提供商并填写 Key 与模型');
    }
    return ai.chat(prompt, system: system, maxTokens: maxTokens);
  }

  Future<Object?> _aiChatTools(Object? args) async {
    final parsed = _parseAiRequest(args, methodName: 'ai.chatTools');
    final ai = _requireAi();
    final reply = await ai.chatWithTools(parsed.messages,
        tools: parsed.tools, maxTokens: parsed.maxTokens);
    return _aiReplyJson(reply);
  }

  /// 流式多轮对话：增量通过 [WebBridgeEventSink] 推给网页的 `antiSIT.on('ai.stream')`，
  /// 返回值仍是完整回复（工具调用在流结束后给出）。`streamId` 由网页生成，
  /// 事件里带上它，网页可以只认自己那一轮。
  Future<Object?> _aiChatToolsStream(Object? args) async {
    final a = args is Map ? args : const {};
    final streamId = '${a['streamId'] ?? ''}'.trim();
    if (streamId.isEmpty) throw ArgumentError('ai.chatToolsStream 要带 {streamId}');
    final parsed = _parseAiRequest(args, methodName: 'ai.chatToolsStream');
    final ai = _requireAi();
    // 模型是 token 级增量，直接每个 chunk 都 runJavaScript 会把 WebView 打满：
    // 攒 ~60ms 再推一次，最后在 finally 里把余量冲干净。
    final text = StringBuffer();
    final reasoning = StringBuffer();
    Timer? timer;
    void flush() {
      if (_events == null) {
        text.clear();
        reasoning.clear();
        return;
      }
      if (reasoning.isNotEmpty) {
        _events!.emit('ai.stream',
            {'streamId': streamId, 'kind': 'reasoning', 'delta': reasoning.toString()});
        reasoning.clear();
      }
      if (text.isNotEmpty) {
        _events!.emit('ai.stream',
            {'streamId': streamId, 'kind': 'text', 'delta': text.toString()});
        text.clear();
      }
    }

    void schedule() {
      timer ??= Timer(const Duration(milliseconds: 60), () {
        timer = null;
        flush();
      });
    }

    try {
      final reply = await ai.chatWithToolsStream(parsed.messages,
          tools: parsed.tools,
          maxTokens: parsed.maxTokens,
          onText: (delta) {
            text.write(delta);
            schedule();
          },
          onReasoning: (delta) {
            reasoning.write(delta);
            schedule();
          });
      return _aiReplyJson(reply);
    } finally {
      timer?.cancel();
      flush();
    }
  }

  static ({List<AiChatMessage> messages, List<AiToolSpec> tools, int maxTokens})
      _parseAiRequest(Object? args, {required String methodName}) {
    if (args is! Map) throw ArgumentError('$methodName 要带 {messages}');
    final rawMessages = args['messages'];
    if (rawMessages is! List || rawMessages.isEmpty) {
      throw ArgumentError('messages 不能为空');
    }
    final messages = <AiChatMessage>[];
    for (final raw in rawMessages) {
      if (raw is! Map) continue;
      final role = '${raw['role'] ?? ''}'.trim();
      if (role.isEmpty) continue;
      final calls = <AiToolCall>[];
      final rawCalls = raw['toolCalls'] ?? raw['tool_calls'];
      if (rawCalls is List) {
        for (final c in rawCalls) {
          if (c is! Map) continue;
          final name = '${c['name'] ?? (c['function'] is Map ? (c['function'] as Map)['name'] : '') ?? ''}'
              .trim();
          if (name.isEmpty) continue;
          final rawArgs = c['arguments'] ??
              (c['function'] is Map ? (c['function'] as Map)['arguments'] : null) ??
              '{}';
          calls.add(AiToolCall(
            id: '${c['id'] ?? ''}'.trim(),
            name: name,
            argumentsJson: rawArgs is String ? rawArgs : jsonEncode(rawArgs),
          ));
        }
      }
      messages.add(AiChatMessage(
        role: role,
        content: '${raw['content'] ?? ''}',
        toolCalls: calls,
        toolCallId: '${raw['toolCallId'] ?? raw['tool_call_id'] ?? ''}',
      ));
    }
    if (messages.isEmpty) throw ArgumentError('messages 里没有有效消息');
    final tools = <AiToolSpec>[];
    final rawTools = args['tools'];
    if (rawTools is List) {
      for (final raw in rawTools) {
        if (raw is! Map) continue;
        final fn = raw['function'] is Map ? raw['function'] as Map : raw;
        final name = '${fn['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        tools.add(AiToolSpec(
          name: name,
          description: '${fn['description'] ?? ''}',
          parameters: fn['parameters'] is Map
              ? Map<String, dynamic>.from(fn['parameters'] as Map)
              : const {'type': 'object', 'properties': {}},
        ));
      }
    }
    final rawMax = args['maxTokens'];
    final maxTokens = rawMax is num ? rawMax.toInt().clamp(256, 4096).toInt() : 4096;
    return (messages: messages, tools: tools, maxTokens: maxTokens);
  }

  static AiCapability _requireAi() {
    final ai = PluginRegistry.I.capability<AiCapability>(PluginIds.ai);
    if (ai == null || !ai.available) {
      throw ArgumentError('AI 还没配好：到「我的 → AI 设置」选择提供商并填写 Key 与模型');
    }
    return ai;
  }

  static Map<String, Object?> _aiReplyJson(AiChatReply reply) => {
        'text': reply.text,
        'reasoning': reply.reasoning,
        'usedTools': reply.usedTools,
        'finishReason': reply.finishReason,
        'toolCalls': [
          for (final c in reply.toolCalls)
            {'id': c.id, 'name': c.name, 'arguments': c.argumentsJson},
        ],
      };

  // ==================== 拓展工坊（内置拓展专用）====================

  Future<Object?> _workshopCall(String method, Object? args) async {
    final a = args is Map ? Map<String, Object?>.from(args) : <String, Object?>{};
    switch (method) {
      case 'workshop.list':
        final drafts = await workshop.listDrafts();
        final installed = ExtensionStore.I.items.map((e) => e.id).toSet();
        return {
          'drafts': [
            for (final d in drafts)
              {...d.toJson(), 'installed': installed.contains(d.id)},
          ],
        };

      case 'workshop.create':
        final name = '${a['name'] ?? '未命名拓展'}'.trim();
        final draft = await workshop.create(name: name.isEmpty ? '未命名拓展' : name);
        return {...draft.toJson(), 'installed': false};

      case 'workshop.renameDraft': {
        final draft = await workshop.renameDraft(
            _argString(a, 'draftId'), '${a['name'] ?? ''}');
        // 已安装的那份顺手同步改名（没装 / id 对不上时 setCard 返回 false，什么也不做）
        await store.setCard(draft.id, name: draft.manifest.name);
        final installed = ExtensionStore.I.items.any((e) => e.id == draft.id);
        return {...draft.toJson(), 'installed': installed};
      }

      case 'workshop.deleteDraft':
        final id = _argString(a, 'draftId');
        if (ExtensionStore.I.isBuiltin(id)) {
          throw ArgumentError('内置拓展不能删除');
        }
        if (ExtensionStore.I.items.any((e) => e.id == id)) {
          throw ArgumentError('「$id」已安装：先到「拓展」页卸载，再删除拓展');
        }
        final draft = await workshop.load(id);
        if (draft == null) throw ArgumentError('拓展不存在或 ext.json 已损坏');
        // 删草稿只可能来自用户点按钮，不属于 Agent 的「完全访问」范围，始终确认
        final ok = await _confirm(
          title: '删除拓展「${draft.manifest.name}」',
          detail: '整个拓展目录（含文件与全部对话记录）会被删除，不可恢复。',
          danger: true,
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝删除拓展'};
        await workshop.deleteDraft(id);
        return {'ok': true};

      case 'workshop.files':
        final id = _argString(a, 'draftId');
        final files = await workshop.listFiles(id);
        return {'files': [for (final f in files) f.toJson()]};

      case 'workshop.read':
        final read = await workshop.readFileVersioned(
            _argString(a, 'draftId'), _argString(a, 'path'));
        return {'content': read.content, 'version': read.version};

      case 'workshop.write':
        final id = _argString(a, 'draftId');
        final path = _argString(a, 'path');
        final content = a['content'] is String ? a['content'] as String : '${a['content'] ?? ''}';
        final expectedVersion = a['expectedVersion'] as String?;
        await workshop.ensureWritable(id, path, expectedVersion);
        final ok = await _approve(
          title: '写入 $path',
          detail: '${content.length} 字符\n\n${_previewText(content)}',
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝写入'};
        final version = await workshop.writeFile(id, path, content,
            expectedVersion: expectedVersion);
        return {'ok': true, 'version': version};

      case 'workshop.delete':
        final id = _argString(a, 'draftId');
        final path = _argString(a, 'path');
        final expectedVersion = a['expectedVersion'] as String?;
        await workshop.ensureDeletable(id, path, expectedVersion);
        final ok = await _approve(
          title: '删除 $path',
          detail: '这个文件会从拓展里删掉。',
          danger: true,
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝删除'};
        await workshop.deleteFile(id, path, expectedVersion: expectedVersion);
        return {'ok': true};

      case 'workshop.session.list':
        final list = await workshop.listConversations(_argString(a, 'draftId'));
        return {'conversations': [for (final c in list) c.toJson()]};

      case 'workshop.session.create':
        final created = await workshop.createConversation(
            _argString(a, 'draftId'),
            title: '${a['title'] ?? '新对话'}');
        return created.toJson();

      case 'workshop.session.rename': {
        final renamed = await workshop.renameConversation(
            _argString(a, 'draftId'),
            _argString(a, 'conversationId'),
            '${a['title'] ?? ''}');
        return renamed.toJson();
      }

      case 'workshop.session.delete':
        final draftId = _argString(a, 'draftId');
        final conversationId = _argString(a, 'conversationId');
        // 删对话同样只从界面触发，始终确认
        final ok = await _confirm(
          title: '删除这段对话',
          detail: '只会删掉这段对话的记录，拓展文件和其它对话不受影响。',
          danger: true,
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝删除对话'};
        await workshop.deleteConversation(draftId, conversationId);
        return {'ok': true};

      case 'workshop.session.get':
        final draftId = _argString(a, 'draftId');
        final conversationId = '${a['conversationId'] ?? ''}'.trim();
        return conversationId.isEmpty
            ? workshop.loadSession(draftId)
            : workshop.loadConversation(draftId, conversationId);

      case 'workshop.session.set':
        final id = _argString(a, 'draftId');
        final data = a['data'] is String ? a['data'] as String : '${a['data'] ?? ''}';
        final conversationId = '${a['conversationId'] ?? ''}'.trim();
        if (conversationId.isEmpty) {
          await workshop.saveSession(id, data);
        } else {
          await workshop.saveConversation(id, conversationId, data);
        }
        return true;

      case 'workshop.skills.list':
        final list = await workshop.listSkills();
        return {'skills': [for (final s in list) s.toJson()]};

      case 'workshop.skills.read':
        final skill = await workshop.readSkill(_argString(a, 'id'));
        return {
          'id': skill.id,
          'name': skill.name,
          'description': skill.description,
          'content': skill.content,
        };

      case 'workshop.skills.install':
        final name = _argString(a, 'name');
        final content =
            a['content'] is String ? a['content'] as String : '${a['content'] ?? ''}';
        final ok = await _approve(
          title: '安装技能「$name」',
          detail: '${content.length} 字符\n\n${_previewText(content)}',
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝安装技能'};
        final skill = await workshop.installSkill(
          name: name,
          description: '${a['description'] ?? ''}',
          content: content,
        );
        return {...skill.toJson(), 'ok': true};

      case 'workshop.skills.delete':
        final id = _argString(a, 'id');
        final confirm = a['userInitiated'] == true ? _confirm : _approve;
        final ok = await confirm(
          title: '删除技能',
          detail: '删除后 Agent 不再能读取这条技能，拓展不受影响。',
          danger: true,
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝删除技能'};
        await workshop.deleteSkill(id);
        return {'ok': true};

      case 'workshop.setFullAccess':
        final enabled = a['enabled'] == true;
        if (enabled && !_fullAccess) {
          // 这是个危险开关：即使已经开了完全访问，也要走原始确认框，不能被自己跳过
          final ok = await _confirm(
            title: '开启完全访问模式',
            detail: '开启后，Agent 写入 / 删除文件、安装拓展和技能将不再逐次弹确认。\n'
                '只在你完全信任当前任务时使用；随时可以在工坊顶部关掉。',
            danger: true,
          );
          if (!ok) return {'ok': false, 'denied': true};
        }
        _fullAccess = enabled;
        return {'ok': true, 'enabled': _fullAccess};

      case 'workshop.validate':
        final problems = await workshop.validate(_argString(a, 'draftId'));
        return {'ok': problems.isEmpty, 'problems': problems};

      case 'workshop.install':
        final draft = await workshop.load(_argString(a, 'draftId'));
        if (draft == null) throw ArgumentError('拓展不存在或 ext.json 已损坏');
        if (ExtensionStore.I.isBuiltin(draft.id)) {
          throw ArgumentError('这是内置拓展的 id，换一个 id 再安装');
        }
        final problems = await workshop.validate(draft.id);
        if (problems.isNotEmpty) throw FormatException(problems.join('\n'));
        final ok = await _approve(
          title: '安装「${draft.manifest.name}」',
          detail: '会把当前拓展复制并加入「拓展」列表。\n'
              'id：${draft.id}\nversion：${draft.manifest.version}\n'
              'permissions：${draft.manifest.permissions.isEmpty ? '无' : draft.manifest.permissions.join(', ')}',
          danger: true,
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝安装'};
        final item = await workshop.install(draft.id);
        return {'ok': true, 'id': item.id, 'name': item.name};

      case 'workshop.preview':
        final draft = await workshop.load(_argString(a, 'draftId'));
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

      case 'workshop.publish':
        final draft = await workshop.load(_argString(a, 'draftId'));
        if (draft == null) throw ArgumentError('拓展不存在或 ext.json 已损坏');
        final problems = await workshop.validate(draft.id);
        if (problems.isNotEmpty) throw FormatException(problems.join('\n'));
        if (context.mounted) {
          await Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              builder: (_) => PublishPage(draft: draft, workshop: workshop),
            ),
          );
        }
        return {'ok': true};

      default:
        throw ArgumentError('未知工坊接口：$method');
    }
  }

  static String _argString(Map<String, Object?> args, String key,
      {bool allowEmpty = false}) {
    final value = '${args[key] ?? ''}'.trim();
    if (!allowEmpty && value.isEmpty) throw ArgumentError('要带 $key');
    return value;
  }

  Future<bool> _approve({
    required String title,
    required String detail,
    bool danger = false,
  }) async {
    // 完全访问模式：所有「写入 / 删除 / 安装」确认都直接放行
    if (_fullAccess) return true;
    return _confirm(title: title, detail: detail, danger: danger);
  }

  Future<bool> _confirm({
    required String title,
    required String detail,
    bool danger = false,
  }) async {
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
          child: SingleChildScrollView(
            child: SelectableText(
              detail,
              style: const TextStyle(
                  fontSize: 12.5, height: 1.5, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: SemColors.danger)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(danger ? '确认执行' : '写入'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  static String _previewText(String content) {
    if (content.length <= 1200) return content;
    return '${content.substring(0, 1200)}\n…（共 ${content.length} 字符）';
  }

  /// 当前配色：把原生色板的**全部令牌**交给拓展，AntiUI 直接映射成 CSS 变量。
  /// 主题插件 / 夜间模式变化时会再推一次 `theme.change`（见 [_onPaletteChanged]）。
  Map<String, Object?> _theme() {
    final p = SemColors.p;
    final brightness = p.isDark ? Brightness.dark : Brightness.light;
    final theme = PluginRegistry.I.theme;
    return {
      'isDark': p.isDark,
      'themeId': theme.id,
      'themeName': theme.name,
      'bg': _hex(p.bg),
      'card': _hex(p.card),
      'cardElevated': _hex(p.cardElevated),
      'navPill': _hex(p.navPill),
      'menuBg': _hex(p.menuBg),
      'border': _hex(p.border),
      'borderStrong': _hex(p.borderStrong),
      'inputFill': _hex(p.inputFill),
      'stripe': _hex(p.stripe),
      'thumb': _hex(p.thumb),
      'overlay': _hex(p.overlay),
      'shadow': _hex(p.shadow),
      'textPrimary': _hex(p.textPrimary),
      'textSecondary': _hex(p.textSecondary),
      'textMuted': _hex(p.textMuted),
      'accent': _hex(p.accent),
      'accentSoft': _hex(p.accentSoft),
      'accentStrong': _hex(p.accentStrong),
      'gold': _hex(p.gold),
      'goldSoft': _hex(p.goldSoft),
      'warning': _hex(p.gold),
      'warningSoft': _hex(p.goldSoft),
      'success': _hex(p.success),
      'successSoft': _hex(p.successSoft),
      'danger': _hex(p.danger),
      'dangerSoft': _hex(p.dangerSoft),
      // 主按钮文字色：深色主题下强调色偏亮，用页面底色才够对比（与 FilledButton 一致）
      'onAccent': _hex(p.isDark ? p.bg : Colors.white),
      // 形状令牌与 buildAppTheme 保持一致，拓展不用猜圆角
      'radiusCard': 16,
      'radiusControl': 12,
      'radiusButton': 16,
      'radiusDialog': 24,
      'radiusSheet': 24,
      'radiusPill': 999,
      // 场景光斑：玻璃主题才有，非玻璃主题是空数组
      'wells': [
        for (final w in theme.wells(brightness))
          {
            'x': w.center.x,
            'y': w.center.y,
            'radius': w.radius,
            'color': _hex(w.color),
          },
      ],
    };
  }

  /// CSS 颜色：带透明度输出 `rgba()`（CSS 的 8 位 hex 是 RRGGBBAA，和 Android 的 ARGB
  /// 相反；玻璃主题深色卡的 card 就是半透明白，丢掉 alpha 会白成一片）。
  static String _hex(Color c) {
    final v = c.toARGB32();
    final a = (v >> 24) & 0xFF;
    final r = (v >> 16) & 0xFF;
    final g = (v >> 8) & 0xFF;
    final b = v & 0xFF;
    String hx(int x) => x.toRadixString(16).padLeft(2, '0');
    if (a == 0xFF) return '#${hx(r)}${hx(g)}${hx(b)}';
    return 'rgba($r, $g, $b, ${(a / 255).toStringAsFixed(3)})';
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

  static String _key(Object? args) {
    final key = args is Map ? '${args['key'] ?? ''}'.trim() : '';
    if (key.isEmpty) throw ArgumentError('要带 key');
    return key;
  }

  static String _secretKey(Object? args) {
    final key = args is Map ? '${args['key'] ?? ''}'.trim() : '';
    if (!ExtSecrets.validKey(key)) {
      throw ArgumentError('密钥名不合法（1–128 位字母 / 数字 / . _ : -）');
    }
    return key;
  }
}
