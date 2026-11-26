import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';
import '../widgets/plugin_graph.dart';

/// 插件 id → 显示名（取不到时回落到 id 本身）。
String pluginDisplayName(PluginRegistry r, String id) => r.byId(id)?.name ?? id;

/// 依赖说明行：核心不可停用 / 依赖 / 可选依赖 / 挂载工具中心 / 被谁依赖。
String pluginDepLine(PluginRegistry r, FeaturePlugin p) {
  final parts = <String>[];
  if (!p.removable) parts.add('核心插件，不可停用');
  if (p.dependencies.isNotEmpty) {
    parts.add('依赖 ${p.dependencies.map((id) => pluginDisplayName(r, id)).join('、')}');
  }
  if (p.optionalDependencies.isNotEmpty) {
    parts.add('可选 ${p.optionalDependencies.map((id) => pluginDisplayName(r, id)).join('、')}');
  }
  if (p.id != PluginIds.tools &&
      p.tools(r).isNotEmpty &&
      r.byId(PluginIds.tools) != null) {
    parts.add('卡片挂在工具中心');
  }
  final dependents = r.dependentsOf(p.id);
  if (dependents.isNotEmpty) {
    parts.add('被 ${dependents.map((id) => pluginDisplayName(r, id)).join('、')} 依赖');
  }
  return parts.join(' · ');
}

/// 提供商开关条目：当前选中的那家带「当前」标记，停用的带「已停用」。
Widget pluginProviderTile(
  PluginRegistry r,
  AiCapability? ai,
  AiProviderPlugin p, {
  required Future<void> Function(AiProviderPlugin, bool) onToggle,
}) {
  final on = r.isProviderEnabled(p.id);
  final cur = ai?.providerId == p.id;
  return SwitchListTile(
    secondary: BrandLogo(asset: p.logo, initial: p.label),
    title: Row(
      children: [
        Flexible(
          child: Text(
            p.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: cur ? FontWeight.w700 : FontWeight.w500,
              color: on ? null : SemColors.textMuted,
            ),
          ),
        ),
        if (cur) ...[
          const SizedBox(width: 6),
          Capsule(
            '当前',
            color: on ? SemColors.accent : const Color(0xFF8A8F98),
          ),
        ],
        if (!on) ...[
          const SizedBox(width: 6),
          const Capsule('已停用', color: Color(0xFF8A8F98)),
        ],
      ],
    ),
    subtitle: Text(p.description, style: const TextStyle(fontSize: 11.5)),
    value: on,
    onChanged: p.removable ? (v) => onToggle(p, v) : null,
  );
}

/// 启停效果卡：底栏与工具宫格长什么样，改开关就能立刻看见。
Widget pluginEffectCard(PluginRegistry r, {required ValueListenable<int> previewTab}) {
  final navLabels = [
    for (final (_, item) in r.navPages(previewTab)) item.label,
  ];
  final tools = r.toolCards;
  return AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '实时效果',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const Spacer(),
            Text(
              '当前主题「${r.theme.name}」',
              style: TextStyle(fontSize: 11, color: SemColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _effectLine(
          '底栏',
          navLabels.isEmpty ? '（没有页面了）' : navLabels.join(' · '),
        ),
        const SizedBox(height: 6),
        _effectLine(
          '工具宫格',
          tools.isEmpty
              ? '（没有启用的工具）'
              : '${tools.length} 个：${tools.map((t) => t.title).join(' · ')}',
        ),
      ],
    ),
  );
}

Widget _effectLine(String label, String value) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    SizedBox(
      width: 60,
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: SemColors.textMuted),
      ),
    ),
    Expanded(
      child: Text(
        value,
        style: TextStyle(
          fontSize: 12.5,
          color: SemColors.textSecondary,
          height: 1.5,
        ),
      ),
    ),
  ],
);

Widget pluginSectionTitle(String title, String trailing) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
  child: Row(
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: SemColors.textSecondary,
        ),
      ),
      const Spacer(),
      Text(
        trailing,
        style: TextStyle(fontSize: 11, color: SemColors.textMuted),
      ),
    ],
  ),
);

/// 清单自检没过时的提示卡：写错的是清单，不是用户的设置。
Widget pluginProblemsCard(PluginRegistry r) => Container(
  margin: const EdgeInsets.only(bottom: 10),
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: SemColors.dangerSoft,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: SemColors.danger.withValues(alpha: 0.3)),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '插件清单有问题',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: SemColors.danger,
        ),
      ),
      const SizedBox(height: 4),
      for (final p in r.problems)
        Text(
          '· $p',
          style: TextStyle(
            fontSize: 12,
            color: SemColors.danger,
            height: 1.6,
          ),
        ),
    ],
  ),
);

/// 依赖关系卡：关系图 + 图例说明 + 选中节点的详情面板。
Widget pluginGraphCard(
  PluginRegistry r, {
  required String? selected,
  required ValueChanged<String> onSelected,
  required Future<void> Function(FeaturePlugin, bool) onToggleFeature,
}) {
  final graph = PluginGraph.fromRegistry(r);
  final layout = PluginGraphLayout.compute(graph);
  final off = {
    for (final f in r.features)
      if (r.isDisabled(f.id)) f.id,
  };
  return AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '依赖关系',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(
          '一列 = 一层依赖，基础插件在右、组合功能在左；箭头指向被依赖的一方。'
          '实线 = 启停联动，长虚线 = 可选依赖，短虚线 = 工具卡片挂在工具中心。'
          '点节点看详情，再点一次取消；双指放大看细节。',
          style: TextStyle(
            fontSize: 11.5,
            color: SemColors.textMuted,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: layout.size.height.clamp(180, 400).toDouble(),
            color: pluginGraphCanvasFill(),
            child: PluginGraphView(
              graph: graph,
              layout: layout,
              selected: selected,
              off: off,
              onTap: onSelected,
            ),
          ),
        ),
        const SizedBox(height: 8),
        pluginSelectedPanel(r,
          selected: selected,
          onToggleFeature: onToggleFeature,
        ),
      ],
    ),
  );
}

/// 关系图下方的详情面板：选中节点显示依赖详情，没选时给一句引导。
Widget pluginSelectedPanel(
  PluginRegistry r, {
  required String? selected,
  required Future<void> Function(FeaturePlugin, bool) onToggleFeature,
}) {
  final id = selected;
  if (id == null) {
    return Text(
      '点关系图里的任意节点，这里显示它的依赖详情。',
      style: TextStyle(fontSize: 12, color: SemColors.textMuted),
    );
  }
  final feature = r.byId(id);
  if (feature == null) {
    final theme = r.themes.firstWhere(
      (t) => t.id == id,
      orElse: () => r.theme,
    );
    final active = r.theme.id == theme.id;
    return _panelBox(
      icon: Icons.palette_outlined,
      title: theme.name,
      description: theme.description,
      extra: '主题插件没有依赖关系',
      action: active
          ? null
          : TextButton(
              onPressed: () => r.setTheme(theme.id),
              child: const Text('用这个主题'),
            ),
    );
  }
  final dep = pluginDepLine(r, feature);
  return _panelBox(
    icon: feature.removable ? Icons.extension_outlined : Icons.lock_outline,
    title: feature.name,
    description: feature.description,
    extra: dep,
    action: Switch(
      value: r.isEnabled(feature.id),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onChanged: feature.removable ? (v) => onToggleFeature(feature, v) : null,
    ),
  );
}

Widget _panelBox({
  required IconData icon,
  required String title,
  required String description,
  String? extra,
  Widget? action,
}) => Container(
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(
    color: SemColors.stripe,
    borderRadius: BorderRadius.circular(10),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 14, color: SemColors.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          if (action != null) action,
        ],
      ),
      const SizedBox(height: 2),
      Text(
        description,
        style: TextStyle(
          fontSize: 12,
          color: SemColors.textSecondary,
          height: 1.5,
        ),
      ),
      if (extra != null && extra.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          extra,
          style: TextStyle(
            fontSize: 11.5,
            color: SemColors.textMuted,
            height: 1.5,
          ),
        ),
      ],
    ],
  ),
);

/// 功能插件条目：开关 + 依赖说明，停用的整行变淡。
Widget pluginFeatureTile(
  PluginRegistry r,
  FeaturePlugin p, {
  required Future<void> Function(FeaturePlugin, bool) onToggle,
}) {
  final dep = pluginDepLine(r, p);
  final on = r.isEnabled(p.id);
  return SwitchListTile(
    secondary: Icon(
      p.removable ? Icons.extension_outlined : Icons.lock_outline,
      color: on ? SemColors.accent : SemColors.textMuted,
    ),
    title: Row(
      children: [
        Flexible(
          child: Text(
            p.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              // 停用的整行跟着变淡：不用看开关也能一眼扫出哪些关着
              color: on ? null : SemColors.textMuted,
            ),
          ),
        ),
        if (!on) ...[
          const SizedBox(width: 6),
          const Capsule('已停用', color: Color(0xFF8A8F98)),
        ],
      ],
    ),
    subtitle: Text(
      dep.isEmpty ? p.description : '${p.description}\n$dep',
      style: const TextStyle(fontSize: 11.5, height: 1.5),
    ),
    isThreeLine: dep.isNotEmpty,
    value: on,
    // 核心插件没有开关（登录与设置宿主停了就没法恢复）
    onChanged: p.removable ? (v) => onToggle(p, v) : null,
  );
}
