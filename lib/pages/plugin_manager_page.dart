import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';
import '../widgets/plugin_graph.dart';
import '../widgets/theme_picker.dart';

/// 插件管理：功能插件的启停、主题切换，以及依赖关系的可视化。
/// 停用有连带效应（被依赖的插件一起停），所以确认弹窗会先把连带清单列出来。
class PluginManagerPage extends StatefulWidget {
  const PluginManagerPage({super.key});

  @override
  State<PluginManagerPage> createState() => _PluginManagerPageState();
}

class _PluginManagerPageState extends State<PluginManagerPage> {
  /// 关系图里选中的节点（再点一次取消）。
  String? _selected;

  /// 只看底栏标签用（不接真实壳层的分页状态，插件收到它也不会去刷新）。
  final ValueNotifier<int> _previewTab = ValueNotifier(0);

  @override
  void dispose() {
    _previewTab.dispose();
    super.dispose();
  }

  PluginRegistry get _r => PluginRegistry.I;

  String _name(String id) => _r.byId(id)?.name ?? id;

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _setEnabled(FeaturePlugin p, bool on) async {
    if (on) {
      final turned = await _r.enable(p.id);
      if (!mounted || turned.isEmpty) return;
      final deps = turned.where((x) => x != p.id).toList();
      _toast(deps.isEmpty
          ? '已启用「${p.name}」'
          : '已启用「${p.name}」，并连带启用依赖：${deps.map(_name).join('、')}');
      return;
    }

    final gone = _r.disableClosure(p.id);
    if (gone.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('连带停用'),
          content: Text('这些插件依赖「${p.name}」，停用它会把它们一起停掉：\n\n'
              '${gone.map((id) => '· ${_name(id)}').join('\n')}\n\n'
              '之后重新启用「${p.name}」不会自动把它们打开。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('一并停用')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final off = await _r.disable(p.id);
    if (!mounted || off.isEmpty) return;
    _toast('已停用：${off.map(_name).join('、')}');
  }

  String _depLine(FeaturePlugin p) {
    final parts = <String>[];
    if (!p.removable) parts.add('核心插件，不可停用');
    if (p.dependencies.isNotEmpty) parts.add('依赖 ${p.dependencies.map(_name).join('、')}');
    if (p.optionalDependencies.isNotEmpty) {
      parts.add('可选 ${p.optionalDependencies.map(_name).join('、')}');
    }
    final dependents = _r.dependentsOf(p.id);
    if (dependents.isNotEmpty) parts.add('被 ${dependents.map(_name).join('、')} 依赖');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('插件管理')),
      body: ListenableBuilder(
        listenable: _r,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            if (_r.problems.isNotEmpty) _problems(),
            _graphCard(),
            const SizedBox(height: 10),
            _effectCard(),
            const SizedBox(height: 10),
            _sectionTitle('功能插件', '${_r.enabled.length}/${_r.features.length} 已启用'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [for (final p in _r.features) _featureTile(p)]),
            ),
            const SizedBox(height: 10),
            _sectionTitle('主题插件', '当前「${_r.theme.name}」'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: const ThemePickerList(),
            ),
          ],
        ),
      ),
    );
  }

  /// 启停的**效果**：改一处开关，底栏/工具宫格长什么样立刻就能看见，
  /// 不用退回去翻页面才知道自己刚刚关掉了什么。
  Widget _effectCard() {
    final navLabels = [
      for (final (_, item) in _r.navPages(_previewTab)) item.label,
    ];
    final tools = _r.toolCards;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('实时效果', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              Text('当前主题「${_r.theme.name}」',
                  style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          _effectLine('底栏', navLabels.isEmpty ? '（没有页面了）' : navLabels.join(' · ')),
          const SizedBox(height: 6),
          _effectLine('工具宫格',
              tools.isEmpty ? '（没有启用的工具）' : '${tools.length} 个：${tools.map((t) => t.title).join(' · ')}'),
        ],
      ),
    );
  }

  Widget _effectLine(String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 12.5, color: SemColors.textSecondary, height: 1.5)),
          ),
        ],
      );

  Widget _sectionTitle(String title, String trailing) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
        child: Row(
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: SemColors.textSecondary)),
            const Spacer(),
            Text(trailing, style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
          ],
        ),
      );

  /// 清单自检没过时最该看见的东西：写错的是清单，不是用户的设置。
  Widget _problems() => Container(
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
            Text('插件清单有问题',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: SemColors.danger)),
            const SizedBox(height: 4),
            for (final p in _r.problems)
              Text('· $p',
                  style: TextStyle(fontSize: 12, color: SemColors.danger, height: 1.6)),
          ],
        ),
      );

  Widget _graphCard() {
    final graph = PluginGraph.fromRegistry(_r);
    final layout = PluginGraphLayout.compute(graph);
    final off = {
      for (final f in _r.features)
        if (_r.isDisabled(f.id)) f.id,
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('依赖关系', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            '一列 = 一层依赖，基础插件在右、组合功能在左；箭头指向被依赖的一方，虚线是可选依赖。'
            '点节点看详情，再点一次取消；图可拖动、双指缩放。',
            style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: layout.size.height.clamp(180, 400).toDouble(),
              color: SemColors.stripe,
              child: PluginGraphView(
                graph: graph,
                layout: layout,
                selected: _selected,
                off: off,
                onTap: (id) => setState(() => _selected = _selected == id ? null : id),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _selectedPanel(),
        ],
      ),
    );
  }

  Widget _selectedPanel() {
    final id = _selected;
    if (id == null) {
      return Text('点关系图里的任意节点，这里显示它的依赖详情。',
          style: TextStyle(fontSize: 12, color: SemColors.textMuted));
    }
    final feature = _r.byId(id);
    if (feature == null) {
      final theme = _r.themes.firstWhere((t) => t.id == id, orElse: () => _r.theme);
      final active = _r.theme.id == theme.id;
      return _panelBox(
        icon: Icons.palette_outlined,
        title: theme.name,
        description: theme.description,
        extra: '主题插件没有依赖关系',
        action: active
            ? null
            : TextButton(
                onPressed: () => _r.setTheme(theme.id),
                child: const Text('用这个主题'),
              ),
      );
    }
    final dep = _depLine(feature);
    return _panelBox(
      icon: feature.removable ? Icons.extension_outlined : Icons.lock_outline,
      title: feature.name,
      description: feature.description,
      extra: dep,
      action: Switch(
        value: _r.isEnabled(feature.id),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: feature.removable ? (v) => _setEnabled(feature, v) : null,
      ),
    );
  }

  Widget _panelBox({
    required IconData icon,
    required String title,
    required String description,
    String? extra,
    Widget? action,
  }) =>
      Container(
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
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                if (action != null) action,
              ],
            ),
            const SizedBox(height: 2),
            Text(description,
                style: TextStyle(fontSize: 12, color: SemColors.textSecondary, height: 1.5)),
            if (extra != null && extra.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(extra, style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.5)),
            ],
          ],
        ),
      );

  Widget _featureTile(FeaturePlugin p) {
    final dep = _depLine(p);
    final on = _r.isEnabled(p.id);
    return SwitchListTile(
      secondary: Icon(
        p.removable ? Icons.extension_outlined : Icons.lock_outline,
        color: on ? SemColors.accent : SemColors.textMuted,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(p.name,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    // 停用的整行跟着变淡：不用看开关也能一眼扫出哪些关着
                    color: on ? null : SemColors.textMuted)),
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
      onChanged: p.removable ? (v) => _setEnabled(p, v) : null,
    );
  }
}
