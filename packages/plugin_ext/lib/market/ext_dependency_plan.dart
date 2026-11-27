import '../extension_item.dart' show compareVersions;
import 'market_entry.dart';

/// 拓展的两种角色（与 Dart 插件体系里的「功能 / 依赖」是两套东西，别混）：
///
/// * **依赖插件**（dependency）：只暴露接口（`api`）给别的拓展调用，自己不画界面，
///   在「拓展」页不占卡片；
/// * **应用插件**（application）：可以创建一个或多个前端组件（卡片 / 页面 / 面板），
///   也能用依赖插件暴露的接口，还能把自己暴露的接口给后面装的应用插件用。
enum ExtRole { application, dependency }

/// 把字符串解析成角色；认不出按应用插件处理（老目录没有这个字段）。
ExtRole extRoleOf(String raw) =>
    raw.trim() == 'dependency' ? ExtRole.dependency : ExtRole.application;

/// 依赖声明：装应用插件要先把这些依赖插件（以及它们自己的依赖）装好。
///
/// 目录里写的是插件 id；解析时按拓扑排序成安装顺序（被依赖的先装）。
class ExtDependency {
  const ExtDependency(this.id, {this.version = ''});

  /// 依赖的拓展 id（= 拓展包 ext.json 里的 id）。
  final String id;

  /// 最低版本（`''` = 不要求）。装了但版本不够 = 缺，要更新。
  final String version;

  factory ExtDependency.parse(Object? raw) {
    if (raw is String) return ExtDependency(raw.trim());
    final map = raw is Map ? raw : const {};
    return ExtDependency(
      '${map['id'] ?? ''}'.trim(),
      version: '${map['version'] ?? ''}'.trim(),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    if (version.isNotEmpty) 'version': version,
  };
}

/// 依赖树上的一个节点：目录里的条目 + 它的角色 / 依赖 / 对外接口。
class ExtNode {
  ExtNode({
    required this.entry,
    required this.role,
    required this.dependencies,
    required this.apis,
  });

  final MarketEntry entry;

  /// 这个条目是依赖插件还是应用插件。
  ExtRole role;

  /// 它自己声明的依赖（未递归）。
  List<ExtDependency> dependencies;

  /// 它对外暴露的接口名（依赖插件必填，应用插件可选）。
  List<String> apis;

  String get id => entry.id;
  String get name => entry.name;

  /// 依赖插件在卡片 / 列表里只显示成一行「提供接口」。
  bool get isDependency => role == ExtRole.dependency;
}

/// 从市场目录解析角色与依赖：目录条目可以带 role / requires / api 字段，
/// 没有这些字段的老目录一律当「应用插件、无依赖」。
List<ExtNode> parseExtNodes(Iterable<MarketEntry> entries) {
  return [
    for (final e in entries)
      ExtNode(
        entry: e,
        role: extRoleOf(e.role),
        dependencies: [for (final d in e.requires) ExtDependency.parse(d)],
        apis: e.api,
      ),
  ];
}

/// 安装计划：一个应用插件要装的东西，按**拓扑排序**（被依赖的先装）。
///
/// [missing] 是要装的（含它自己），[installed] 是已经装好且版本够的，
/// [unresolved] 是目录里找不到的依赖（装不了）。
class ExtInstallPlan {
  const ExtInstallPlan({
    required this.order,
    required this.missing,
    required this.installed,
    required this.unresolved,
    required this.conflicts,
  });

  /// 安装顺序（拓扑序，被依赖的在前）：含应用插件自己。
  final List<ExtNode> order;

  /// 需要下载安装的条目（`order` 的子集，去掉已装够版本的）。
  final List<ExtNode> missing;

  /// 已经装好、版本够的依赖（不需要动）。
  final List<ExtNode> installed;

  /// 目录里根本没有的依赖 id（先在市场里补，或换一个源）。
  final List<String> unresolved;

  /// 版本不够、已装的是旧版：要更新它（这些也在 [missing] 里）。
  final List<String> conflicts;

  bool get canInstall => unresolved.isEmpty;

  /// 下载总量（字节，未知的按 0 算）。
  int get totalBytes => missing.fold(0, (sum, n) => sum + n.entry.size);

  /// 是不是只装它自己（普通应用插件，没有依赖）。
  bool get single => missing.length <= 1 && order.length <= 1;
}

/// 依赖图：目录里所有条目的 id → 节点，用来算安装计划。
///
/// `installed` 传「已经装好的 id → 版本」；版本不够的依赖算「要更新」。
ExtInstallPlan planExtInstall({
  required ExtNode target,
  required Map<String, ExtNode> catalog,
  required Map<String, String> installed,
}) {
  final order = <ExtNode>[];
  final seen = <String>{};
  final unresolved = <String>[];
  final conflicts = <String>[];
  final cycle = <String>[];

  void visit(ExtNode node, List<String> path) {
    if (seen.contains(node.id)) return;
    if (path.contains(node.id)) {
      cycle.addAll([...path.sublist(path.indexOf(node.id)), node.id]);
      return;
    }
    for (final dep in node.dependencies) {
      final next = catalog[dep.id];
      if (next == null) {
        if (!unresolved.contains(dep.id)) unresolved.add(dep.id);
        continue;
      }
      final have = installed[dep.id];
      if (have != null &&
          dep.version.isNotEmpty &&
          compareVersions(have, dep.version) < 0) {
        if (!conflicts.contains(dep.id)) conflicts.add(dep.id);
      }
      visit(next, [...path, node.id]);
    }
    if (seen.add(node.id)) order.add(node);
  }

  visit(target, const []);

  // 没装过的、以及装过但版本不够的，都要下载（后者先更新再装应用插件）
  final missing = <ExtNode>[
    for (final n in order)
      if (!installed.containsKey(n.id) || conflicts.contains(n.id)) n,
  ];
  final installedOk = <ExtNode>[
    for (final n in order)
      if (installed.containsKey(n.id) && !conflicts.contains(n.id)) n,
  ];
  return ExtInstallPlan(
    order: order,
    missing: missing,
    installed: installedOk,
    unresolved: unresolved,
    conflicts: conflicts,
  );
}

/// 从安装计划生成树：`[应用插件, 它的依赖 …]`，用于下载界面的树状图。
///
/// 每个节点带自己的深度（顶层 = 0），同一依赖被多个应用插件共用时只出现一次。
class ExtTreeRow {
  const ExtTreeRow({
    required this.node,
    required this.depth,
    required this.needed,
    this.state = ExtTreeState.pending,
    this.error = '',
  });

  final ExtNode node;
  final int depth;

  /// 这次安装是否需要下载它（false = 已经装好、只是画出来看依赖关系）。
  final bool needed;

  final ExtTreeState state;
  final String error;

  ExtTreeRow copyWith({ExtTreeState? state, String? error}) => ExtTreeRow(
    node: node,
    depth: depth,
    needed: needed,
    state: state ?? this.state,
    error: error ?? this.error,
  );
}

/// 下载 / 安装过程中一个节点的状态（树状图按它上色）。
enum ExtTreeState { pending, downloading, done, skipped, failed }

/// 把安装计划摊成树行（前序遍历，父子相邻；共用依赖只画一次）。
List<ExtTreeRow> extTreeRows(
  ExtInstallPlan plan, {
  Map<String, String> installed = const {},
}) {
  final rows = <ExtTreeRow>[];
  final seen = <String>{};

  void walk(ExtNode node, int depth) {
    if (!seen.add(node.id)) return;
    final already =
        installed.containsKey(node.id) && !plan.conflicts.contains(node.id);
    rows.add(
      ExtTreeRow(
        node: node,
        depth: depth,
        needed: !already,
        state: already ? ExtTreeState.skipped : ExtTreeState.pending,
      ),
    );
    // 依赖按目录顺序展开（共享依赖只在第一次出现的地方铺开）
    for (final dep in node.dependencies) {
      final next = plan.order.firstWhere(
        (n) => n.id == dep.id,
        orElse: () => node,
      );
      if (next.id != dep.id) continue;
      walk(next, depth + 1);
    }
  }

  // 顶层 = 计划里没有「被别的节点依赖」的那些（通常是应用插件自己）。
  final dependedOn = <String>{
    for (final n in plan.order)
      for (final d in n.dependencies) d.id,
  };
  for (final n in plan.order) {
    if (!dependedOn.contains(n.id)) walk(n, 0);
  }
  for (final n in plan.order) {
    walk(n, 0); // 兜底：环 / 孤立节点也要画出来
  }
  return rows;
}
