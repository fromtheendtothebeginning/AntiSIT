import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'cordis_bundle.dart';
import 'ext_icon.dart';
import 'ext_permissions.dart';
import 'extension_item.dart';
import 'extension_store.dart';
import 'workshop/workshop_store.dart';

/// 拓展网页能用的接口（方法表见 `docs/extensions.md`，网页侧统一 `antiSIT.call(...)`）：
///
/// | 方法 | 参数 | 返回 |
/// |---|---|---|
/// | `theme` | — | 当前配色的十六进制值（`accent` / `bg` / `card` / `textPrimary` / …） |
/// | `toast` | `{text}` | 弹一条 App 风格的提示 |
/// | `close` | — | 关掉当前网页（回拓展列表） |
/// | `card.setName` | `{text}` | 换卡片上的名称（≤ 20 字；id 不变） |
/// | `card.setDesc` | `{text}` | 换卡片上的简介（≤ 60 字；空串 = 不显示简介） |
/// | `card.setIcon` | `{text}` | 换卡片上的图标（`line:<name>` 镂空图标、图片网址，或 ≤ 4 字的文字 / emoji；空串 = 用网站 favicon） |
/// | `storage.get` | `{key}` | 该拓展自己存的任意 JSON；没有则 null |
/// | `storage.set` | `{key, value}` | true |
/// | `storage.remove` | `{key}` | true |
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

  /// 内核 → 网页的下行通道（流式 AI 增量用）；页面关掉后为 null。
  WebBridgeEventSink? _events;

  /// 完全访问模式：跳过写入 / 删除 / 安装的原生确认（只由工坊自己的开关打开）。
  bool _fullAccess = false;

  @override
  void attachEventSink(WebBridgeEventSink? sink) {
    _events = sink;
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
      case 'storage.get':
        return store.dataGet(extId, _key(args));
      case 'storage.set':
        if (args is! Map) throw ArgumentError('storage.set 要带 {key, value}');
        await store.dataSet(extId, _key(args), args['value']);
        return true;
      case 'storage.remove':
        await store.dataRemove(extId, _key(args));
        return true;
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

      case 'workshop.deleteDraft':
        final id = _argString(a, 'draftId');
        if (ExtensionStore.I.isBuiltin(id)) {
          throw ArgumentError('内置拓展的草稿不能删除');
        }
        if (ExtensionStore.I.items.any((e) => e.id == id)) {
          throw ArgumentError('「$id」已安装：先到「拓展」页卸载，再删除草稿');
        }
        final draft = await workshop.load(id);
        if (draft == null) throw ArgumentError('草稿不存在或 ext.json 已损坏');
        // 删草稿只可能来自用户点按钮，不属于 Agent 的「完全访问」范围，始终确认
        final ok = await _confirm(
          title: '删除草稿「${draft.manifest.name}」',
          detail: '整个草稿目录（含文件与全部对话记录）会被删除，不可恢复。',
          danger: true,
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝删除草稿'};
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
          detail: '这个文件会从草稿里删掉。',
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

      case 'workshop.session.delete':
        final draftId = _argString(a, 'draftId');
        final conversationId = _argString(a, 'conversationId');
        // 删对话同样只从界面触发，始终确认
        final ok = await _confirm(
          title: '删除这段对话',
          detail: '只会删掉这段对话的记录，草稿文件和其它对话不受影响。',
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
          detail: '删除后 Agent 不再能读取这条技能，草稿与拓展不受影响。',
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
        if (draft == null) throw ArgumentError('草稿不存在或 ext.json 已损坏');
        if (ExtensionStore.I.isBuiltin(draft.id)) {
          throw ArgumentError('这是内置拓展的 id，换一个 id 再安装');
        }
        final problems = await workshop.validate(draft.id);
        if (problems.isNotEmpty) throw FormatException(problems.join('\n'));
        final ok = await _approve(
          title: '安装「${draft.manifest.name}」',
          detail: '会把草稿复制成正式拓展并加入「拓展」列表。\n'
              'id：${draft.id}\nversion：${draft.manifest.version}\n'
              'permissions：${draft.manifest.permissions.isEmpty ? '无' : draft.manifest.permissions.join(', ')}',
          danger: true,
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝安装'};
        final item = await workshop.install(draft.id);
        return {'ok': true, 'id': item.id, 'name': item.name};

      case 'workshop.preview':
        final draft = await workshop.load(_argString(a, 'draftId'));
        if (draft == null) throw ArgumentError('草稿不存在或 ext.json 已损坏');
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

  /// 当前配色：拓展照着 App 的样子画，不用自己猜深浅色。
  Map<String, Object?> _theme() => {
        'isDark': SemColors.isDark,
        'accent': _hex(SemColors.accent),
        'accentSoft': _hex(SemColors.accentSoft),
        'bg': _hex(SemColors.bg),
        'card': _hex(SemColors.card),
        'border': _hex(SemColors.border),
        'textPrimary': _hex(SemColors.textPrimary),
        'textSecondary': _hex(SemColors.textSecondary),
        'textMuted': _hex(SemColors.textMuted),
        'danger': _hex(SemColors.danger),
        'success': _hex(SemColors.success),
      };

  /// '#RRGGBB'（与主题导入导出用同一套写法）。
  static String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  void _toast(Object? args) {
    if (!context.mounted) return;
    final text = args is Map ? '${args['text'] ?? ''}' : '$args';
    if (text.trim().isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating));
  }

  static String _key(Object? args) {
    final key = args is Map ? '${args['key'] ?? ''}'.trim() : '';
    if (key.isEmpty) throw ArgumentError('要带 key');
    return key;
  }
}
