import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'ext_bridge_args.dart';
import 'publish/publish_page.dart';
import 'extension_store.dart';
import 'workshop/workshop_conversations.dart';
import 'workshop/workshop_skills.dart';
import 'workshop/workshop_store.dart';

/// 「拓展工坊」通道：把 `workshop.*` 方法分派到 [WorkshopStore]。
///
/// 只给内置工坊（`ExtBridge.workshopExtId`）用；写入 / 删除 / 安装默认都要
/// [fullAccess] 之外的逐次原生确认。
class WorkshopChannel {
  WorkshopChannel({
    required this.store,
    required this.workshop,
    required this.context,
  });

  final ExtensionStore store;
  final WorkshopStore workshop;
  final BuildContext context;

  /// 完全访问模式：跳过写入 / 删除 / 安装的原生确认（只由工坊自己的开关打开）。
  bool fullAccess = false;

  Future<Object?> call(String method, Object? args) async {
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
            extArgString(a, 'draftId'), '${a['name'] ?? ''}');
        // 已安装的那份顺手同步改名（没装 / id 对不上时 setCard 返回 false，什么也不做）
        await store.setCard(draft.id, name: draft.manifest.name);
        final installed = ExtensionStore.I.items.any((e) => e.id == draft.id);
        return {...draft.toJson(), 'installed': installed};
      }

      case 'workshop.deleteDraft':
        final id = extArgString(a, 'draftId');
        if (ExtensionStore.I.isBuiltin(id)) {
          throw ArgumentError('内置拓展不能删除');
        }
        if (ExtensionStore.I.items.any((e) => e.id == id)) {
          throw ArgumentError('「$id」已安装：先到「拓展」页卸载，再删除拓展');
        }
        final draft = await workshop.load(id);
        if (draft == null) throw ArgumentError('拓展不存在或 ext.json 已损坏');
        // 删草稿只可能来自用户点按钮，不属于 Agent 的「完全访问」范围，始终确认
        final ok = await confirm(
          title: '删除拓展「${draft.manifest.name}」',
          detail: '整个拓展目录（含文件与全部对话记录）会被删除，不可恢复。',
          danger: true,
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝删除拓展'};
        await workshop.deleteDraft(id);
        return {'ok': true};

      case 'workshop.files':
        final id = extArgString(a, 'draftId');
        final files = await workshop.listFiles(id);
        return {'files': [for (final f in files) f.toJson()]};

      case 'workshop.read':
        final read = await workshop.readFileVersioned(
            extArgString(a, 'draftId'), extArgString(a, 'path'));
        return {'content': read.content, 'version': read.version};

      case 'workshop.write':
        final id = extArgString(a, 'draftId');
        final path = extArgString(a, 'path');
        final content = a['content'] is String ? a['content'] as String : '${a['content'] ?? ''}';
        final expectedVersion = a['expectedVersion'] as String?;
        await workshop.ensureWritable(id, path, expectedVersion);
        final ok = await approve(
          title: '写入 $path',
          detail: '${content.length} 字符\n\n${extPreviewText(content)}',
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝写入'};
        final version = await workshop.writeFile(id, path, content,
            expectedVersion: expectedVersion);
        return {'ok': true, 'version': version};

      case 'workshop.delete':
        final id = extArgString(a, 'draftId');
        final path = extArgString(a, 'path');
        final expectedVersion = a['expectedVersion'] as String?;
        await workshop.ensureDeletable(id, path, expectedVersion);
        final ok = await approve(
          title: '删除 $path',
          detail: '这个文件会从拓展里删掉。',
          danger: true,
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝删除'};
        await workshop.deleteFile(id, path, expectedVersion: expectedVersion);
        return {'ok': true};

      case 'workshop.session.list':
        final list = await workshop.listConversations(extArgString(a, 'draftId'));
        return {'conversations': [for (final c in list) c.toJson()]};

      case 'workshop.session.create':
        final created = await workshop.createConversation(
            extArgString(a, 'draftId'),
            title: '${a['title'] ?? '新对话'}');
        return created.toJson();

      case 'workshop.session.rename': {
        final renamed = await workshop.renameConversation(
            extArgString(a, 'draftId'),
            extArgString(a, 'conversationId'),
            '${a['title'] ?? ''}');
        return renamed.toJson();
      }

      case 'workshop.session.delete':
        final draftId = extArgString(a, 'draftId');
        final conversationId = extArgString(a, 'conversationId');
        // 删对话同样只从界面触发，始终确认
        final ok = await confirm(
          title: '删除这段对话',
          detail: '只会删掉这段对话的记录，拓展文件和其它对话不受影响。',
          danger: true,
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝删除对话'};
        await workshop.deleteConversation(draftId, conversationId);
        return {'ok': true};

      case 'workshop.session.get':
        final draftId = extArgString(a, 'draftId');
        final conversationId = '${a['conversationId'] ?? ''}'.trim();
        return conversationId.isEmpty
            ? workshop.loadSession(draftId)
            : workshop.loadConversation(draftId, conversationId);

      case 'workshop.session.set':
        final id = extArgString(a, 'draftId');
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
        final skill = await workshop.readSkill(extArgString(a, 'id'));
        return {
          'id': skill.id,
          'name': skill.name,
          'description': skill.description,
          'content': skill.content,
        };

      case 'workshop.skills.install':
        final name = extArgString(a, 'name');
        final content =
            a['content'] is String ? a['content'] as String : '${a['content'] ?? ''}';
        final ok = await approve(
          title: '安装技能「$name」',
          detail: '${content.length} 字符\n\n${extPreviewText(content)}',
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝安装技能'};
        final skill = await workshop.installSkill(
          name: name,
          description: '${a['description'] ?? ''}',
          content: content,
        );
        return {...skill.toJson(), 'ok': true};

      case 'workshop.skills.delete':
        final id = extArgString(a, 'id');
        final confirmFn = a['userInitiated'] == true ? confirm : approve;
        final ok = await confirmFn(
          title: '删除技能',
          detail: '删除后 Agent 不再能读取这条技能，拓展不受影响。',
          danger: true,
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝删除技能'};
        await workshop.deleteSkill(id);
        return {'ok': true};

      case 'workshop.setFullAccess':
        final enabled = a['enabled'] == true;
        if (enabled && !fullAccess) {
          // 这是个危险开关：即使已经开了完全访问，也要走原始确认框，不能被自己跳过
          final ok = await confirm(
            title: '开启完全访问模式',
            detail: '开启后，Agent 写入 / 删除文件、安装拓展和技能将不再逐次弹确认。\n'
                '只在你完全信任当前任务时使用；随时可以在工坊顶部关掉。',
            danger: true,
          );
          if (!ok) return {'ok': false, 'denied': true};
        }
        fullAccess = enabled;
        return {'ok': true, 'enabled': fullAccess};

      case 'workshop.validate':
        final problems = await workshop.validate(extArgString(a, 'draftId'));
        return {'ok': problems.isEmpty, 'problems': problems};

      case 'workshop.install':
        final draft = await workshop.load(extArgString(a, 'draftId'));
        if (draft == null) throw ArgumentError('拓展不存在或 ext.json 已损坏');
        if (ExtensionStore.I.isBuiltin(draft.id)) {
          throw ArgumentError('这是内置拓展的 id，换一个 id 再安装');
        }
        final problems = await workshop.validate(draft.id);
        if (problems.isNotEmpty) throw FormatException(problems.join('\n'));
        final ok = await approve(
          title: '安装「${draft.manifest.name}」',
          detail: '会把当前拓展复制并加入「拓展」列表。\n'
              'id：${draft.id}\nversion：${draft.manifest.version}\n'
              'permissions：${draft.manifest.permissions.isEmpty ? '无' : draft.manifest.permissions.join(', ')}',
          danger: true,
        );
        if (!ok) return {'ok': false, 'denied': true, 'reason': '用户拒绝安装'};
        final item = await workshop.install(draft.id);
        return {'ok': true, 'id': item.id, 'name': item.name};

      case 'workshop.publish':
        final draft = await workshop.load(extArgString(a, 'draftId'));
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

  /// 完全访问模式下直接放行，否则弹原生确认框。
  Future<bool> approve({
    required String title,
    required String detail,
    bool danger = false,
  }) async {
    if (fullAccess) return true;
    return confirm(title: title, detail: detail, danger: danger);
  }

  /// 弹一个不可跳过的原生确认框。
  Future<bool> confirm({
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
}
