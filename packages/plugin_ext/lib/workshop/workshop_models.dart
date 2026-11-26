import '../cordis_bundle.dart';

/// 拓展工坊的一个草稿。
class WorkshopDraft {
  const WorkshopDraft({required this.id, required this.dir, required this.manifest});

  final String id;
  final String dir;
  final CordisManifest manifest;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': manifest.name,
        'desc': manifest.desc,
        'version': manifest.version,
        'permissions': manifest.permissions,
      };
}

/// 草稿文件树里的一项。
class WorkshopFile {
  const WorkshopFile({required this.path, required this.size});

  final String path;
  final int size;

  Map<String, Object?> toJson() => {'path': path, 'size': size};
}

/// 一次读取的结果：内容 + 内容哈希。
///
/// 哈希是「读后写」的版本凭据：写回时必须带上它，文件在这期间被改过就拒绝写入。
class WorkshopFileContent {
  const WorkshopFileContent({required this.content, required this.version});

  final String content;
  final String version;
}

/// 一个草稿下的一段对话（同一插件可以有多段对话）。
class WorkshopConversation {
  const WorkshopConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  final String id;
  final String title;

  /// 最后更新时间（毫秒时间戳），列表按它倒序。
  final int updatedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt,
      };
}

/// 已安装的一条 Agent 技能（可复用的指令文档，不是可执行代码）。
class WorkshopSkill {
  const WorkshopSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final int updatedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'updatedAt': updatedAt,
      };
}

/// 技能全文（Agent 用 `read_skill` 取）。
class WorkshopSkillContent {
  const WorkshopSkillContent({
    required this.id,
    required this.name,
    required this.description,
    required this.content,
  });

  final String id;
  final String name;
  final String description;
  final String content;
}
