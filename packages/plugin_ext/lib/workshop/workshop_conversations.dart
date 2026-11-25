import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'workshop_models.dart';
import 'workshop_store.dart';

Future<File> _legacySessionFile(WorkshopStore store, String draftId) async =>
    File(p.join(await store.draftDir(draftId), '.workshop', 'session.json'));

Future<File> _conversationFile(
    WorkshopStore store, String draftId, String conversationId) async {
  if (!WorkshopStore.conversationIdPattern.hasMatch(conversationId)) {
    throw const FormatException('对话 id 不合法');
  }
  return File(p.join(await store.draftDir(draftId), '.workshop', 'sessions',
      '$conversationId.json'));
}

Future<File> _conversationFileFor(
        WorkshopStore store, String draftId, String conversationId) async =>
    conversationId == WorkshopStore.defaultConversationId
        ? _legacySessionFile(store, draftId)
        : _conversationFile(store, draftId, conversationId);

WorkshopConversation? _conversationMeta(File file, String id) {
  try {
    Map? data;
    if (file.lengthSync() <= WorkshopStore.maxSessionBytes) {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) data = decoded;
    }
    final title = '${data?['title'] ?? ''}'.trim();
    final rawUpdated = data?['updatedAt'];
    final updated = rawUpdated is num
        ? rawUpdated.toInt()
        : file.lastModifiedSync().millisecondsSinceEpoch;
    return WorkshopConversation(
        id: id,
        title: title.isEmpty ? '未命名对话' : title,
        updatedAt: updated);
  } catch (e) {
    debugPrint('[ext-workshop] 对话 $id 读不了，已跳过：$e');
    return null;
  }
}

/// 草稿下的对话日志：一段对话一个 JSON，放在草稿的 `.workshop/sessions/`。
///
/// 旧版单文件 `session.json` 仍可读，作为默认对话。
extension WorkshopConversations on WorkshopStore {
  /// 当前草稿下的全部对话（新的在前）。
  Future<List<WorkshopConversation>> listConversations(String draftId) async {
    final out = <WorkshopConversation>[];
    final legacy = await _legacySessionFile(this, draftId);
    if (legacy.existsSync()) {
      final meta = _conversationMeta(legacy, WorkshopStore.defaultConversationId);
      if (meta != null) out.add(meta);
    }
    final dir = Directory(p.join(await draftDir(draftId), '.workshop', 'sessions'));
    if (dir.existsSync()) {
      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final id = p.basenameWithoutExtension(entity.path);
        if (!WorkshopStore.conversationIdPattern.hasMatch(id)) continue;
        final meta = _conversationMeta(entity, id);
        if (meta != null) out.add(meta);
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<String?> loadConversation(String draftId, String conversationId) async {
    final id =
        conversationId.trim().isEmpty ? WorkshopStore.defaultConversationId : conversationId.trim();
    final file = await _conversationFileFor(this, draftId, id);
    if (!file.existsSync()) return null;
    if (file.lengthSync() > WorkshopStore.maxSessionBytes) {
      throw FormatException(
          '会话日志太大（${(file.lengthSync() / 1024).round()} KB，上限 ${WorkshopStore.maxSessionBytes ~/ 1024} KB）');
    }
    return file.readAsStringSync();
  }

  Future<void> saveConversation(
      String draftId, String conversationId, String data) async {
    final id =
        conversationId.trim().isEmpty ? WorkshopStore.defaultConversationId : conversationId.trim();
    final bytes = utf8.encode(data);
    if (bytes.length > WorkshopStore.maxSessionBytes) {
      throw FormatException(
          '会话日志太大（${(bytes.length / 1024).round()} KB，上限 ${WorkshopStore.maxSessionBytes ~/ 1024} KB）');
    }
    final file = await _conversationFileFor(this, draftId, id);
    file.parent.createSync(recursive: true);
    final temp = File('${file.path}.tmp');
    temp.writeAsBytesSync(bytes, flush: true);
    try {
      temp.renameSync(file.path);
    } catch (_) {
      // 个别平台不允许 rename 覆盖已有文件：退回直接写，并清掉临时文件。
      file.writeAsBytesSync(bytes, flush: true);
      if (temp.existsSync()) temp.deleteSync();
    }
  }

  /// 新建一段空对话；标题由前端在第一条用户消息后更新。
  Future<WorkshopConversation> createConversation(String draftId,
      {String title = '新对话'}) async {
    final dir =
        Directory(p.join(await draftDir(draftId), '.workshop', 'sessions'));
    dir.createSync(recursive: true);
    final base = 'c${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    var id = base;
    var n = 0;
    while (File(p.join(dir.path, '$id.json')).existsSync()) {
      n += 1;
      id = '${base}_$n';
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final safeTitle = title.trim().isEmpty ? '新对话' : title.trim();
    await saveConversation(
        draftId,
        id,
        jsonEncode({
          'version': 1,
          'draftId': draftId,
          'conversationId': id,
          'title': safeTitle,
          'createdAt': now,
          'updatedAt': now,
          'seq': 0,
          'turnSeq': 0,
          'events': <Object?>[],
        }));
    return WorkshopConversation(id: id, title: safeTitle, updatedAt: now);
  }

  Future<void> deleteConversation(String draftId, String conversationId) async {
    final id =
        conversationId.trim().isEmpty ? WorkshopStore.defaultConversationId : conversationId.trim();
    final file = await _conversationFileFor(this, draftId, id);
    if (file.existsSync()) file.deleteSync();
  }

  /// 重命名对话：只改会话文件的 title；文件还不存在时也建一份最小的，
  /// 保证列表里立刻能看到新名字。
  Future<WorkshopConversation> renameConversation(
      String draftId, String conversationId, String title) async {
    final id =
        conversationId.trim().isEmpty ? WorkshopStore.defaultConversationId : conversationId.trim();
    final clean = title.trim();
    if (clean.isEmpty) throw const FormatException('对话名不能为空');
    final safe = clean.length > 48 ? clean.substring(0, 48) : clean;
    final raw = await loadConversation(draftId, id);
    var data = <String, dynamic>{};
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        // 坏日志不挡改名：保留可解析的字段做不到，就按最小会话重建
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    data['title'] = safe;
    data['updatedAt'] = now;
    data['version'] ??= 1;
    data['seq'] ??= 0;
    data['turnSeq'] ??= 0;
    data['events'] ??= <Object?>[];
    await saveConversation(draftId, id, jsonEncode(data));
    return WorkshopConversation(id: id, title: safe, updatedAt: now);
  }

  /// 兼容旧接口：不指定对话时读写默认会话。
  Future<String?> loadSession(String draftId) =>
      loadConversation(draftId, WorkshopStore.defaultConversationId);

  Future<void> saveSession(String draftId, String data) =>
      saveConversation(draftId, WorkshopStore.defaultConversationId, data);
}
