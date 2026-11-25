import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'workshop_models.dart';
import 'workshop_store.dart';

final RegExp _skillIdPattern = RegExp(r'^s[0-9a-z_]{2,63}$');

Future<Directory> _skillsDir(WorkshopStore store) async =>
    Directory(p.join(await store.rootDir(), '.skills'));

Future<File> _skillFile(WorkshopStore store, String id) async {
  if (!_skillIdPattern.hasMatch(id)) {
    throw const FormatException('技能 id 不合法');
  }
  final dir = await _skillsDir(store);
  final file = File(p.join(dir.path, '$id.json'));
  if (!p.isWithin(dir.path, file.path)) {
    throw const FormatException('技能路径越界');
  }
  return file;
}

Map<String, Object?>? _readSkillMap(File file) {
  try {
    if (file.lengthSync() > WorkshopStore.maxSkillBytes) return null;
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) return null;
    final id = '${decoded['id'] ?? ''}'.trim();
    final name = '${decoded['name'] ?? ''}'.trim();
    final content = '${decoded['content'] ?? ''}';
    if (!_skillIdPattern.hasMatch(id) || name.isEmpty || content.trim().isEmpty) {
      return null;
    }
    return {
      'id': id,
      'name': name,
      'description': '${decoded['description'] ?? ''}'.trim(),
      'content': content,
      'createdAt': decoded['createdAt'] is num
          ? (decoded['createdAt'] as num).toInt()
          : 0,
      'updatedAt': decoded['updatedAt'] is num
          ? (decoded['updatedAt'] as num).toInt()
          : 0,
    };
  } catch (e) {
    debugPrint('[ext-workshop] 技能 ${file.path} 读不了，已跳过：$e');
    return null;
  }
}

/// Agent 技能库：全局共享的指令文档，落在 `<文档目录>/ext-workshop/.skills/`。
extension WorkshopSkills on WorkshopStore {
  Future<List<WorkshopSkill>> listSkills() async {
    final dir = await _skillsDir(this);
    if (!dir.existsSync()) return const [];
    final out = <WorkshopSkill>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final data = _readSkillMap(entity);
      if (data == null) continue;
      out.add(WorkshopSkill(
        id: '${data['id']}',
        name: '${data['name']}',
        description: '${data['description']}',
        updatedAt: data['updatedAt'] is int ? data['updatedAt'] as int : 0,
      ));
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<WorkshopSkillContent> readSkill(String id) async {
    final file = await _skillFile(this, id);
    final data = _readSkillMap(file);
    if (data == null) throw const FormatException('技能不存在或已损坏');
    return WorkshopSkillContent(
      id: '${data['id']}',
      name: '${data['name']}',
      description: '${data['description']}',
      content: '${data['content']}',
    );
  }

  /// 安装 / 更新一条技能（同名视为更新，id 不变）。
  Future<WorkshopSkill> installSkill({
    required String name,
    String description = '',
    required String content,
  }) async {
    final cleanName = name.trim();
    final cleanDesc = description.trim();
    final cleanContent = content.trim();
    if (cleanName.isEmpty) throw const FormatException('技能名称不能为空');
    if (cleanName.length > 40) throw const FormatException('技能名称最多 40 个字');
    if (cleanDesc.length > 160) throw const FormatException('技能说明最多 160 个字');
    if (cleanContent.isEmpty) throw const FormatException('技能内容不能为空');
    if (utf8.encode(cleanContent).length > WorkshopStore.maxSkillBytes) {
      throw FormatException('技能内容太大（上限 ${WorkshopStore.maxSkillBytes ~/ 1024} KB）');
    }

    final existing = await listSkills();
    final sameName = existing.where(
        (s) => s.name.toLowerCase() == cleanName.toLowerCase());
    if (sameName.isEmpty && existing.length >= WorkshopStore.maxSkills) {
      throw FormatException(
          '技能库已满（最多 ${WorkshopStore.maxSkills} 条），先删掉不用的再装');
    }
    final dir = await _skillsDir(this);
    dir.createSync(recursive: true);
    var id = sameName.isEmpty
        ? 's${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        : sameName.first.id;
    var n = 0;
    while (sameName.isEmpty && File(p.join(dir.path, '$id.json')).existsSync()) {
      n += 1;
      id = 's${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_$n';
    }
    var createdAt = DateTime.now().millisecondsSinceEpoch;
    final oldFile = File(p.join(dir.path, '$id.json'));
    final old = oldFile.existsSync() ? _readSkillMap(oldFile) : null;
    if (old != null && old['createdAt'] is int && (old['createdAt'] as int) > 0) {
      createdAt = old['createdAt'] as int;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = jsonEncode({
      'id': id,
      'name': cleanName,
      'description': cleanDesc,
      'content': cleanContent,
      'createdAt': createdAt,
      'updatedAt': now,
    });
    await _skillFile(this, id); // 先校验 id
    final bytes = utf8.encode(payload);
    if (bytes.length > WorkshopStore.maxSkillBytes) {
      throw FormatException('技能内容太大（上限 ${WorkshopStore.maxSkillBytes ~/ 1024} KB）');
    }
    oldFile.writeAsBytesSync(bytes, flush: true);
    return WorkshopSkill(
        id: id, name: cleanName, description: cleanDesc, updatedAt: now);
  }

  Future<void> deleteSkill(String id) async {
    final file = await _skillFile(this, id);
    if (file.existsSync()) file.deleteSync();
  }
}
