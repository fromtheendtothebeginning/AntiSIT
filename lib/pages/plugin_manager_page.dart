import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';
import '../widgets/plugin_graph.dart';

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
    if (p.id != PluginIds.tools && p.tools(_r).isNotEmpty && _r.byId(PluginIds.tools) != null) {
      parts.add('卡片挂在工具中心');
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
            const SizedBox(height: 10),
            _sectionTitle(
                'AI 提供商',
                '${_r.enabledProviders.length}/${_r.providers.length} 已启用 · '
                    '当前「${_ai?.providerLabel ?? '未装 / 已停用'}」'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [for (final p in _r.providerList) _providerTile(p)]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text('停用的提供商不会出现在「我的 → 设置 → AI 设置」的选择器里；'
                  '要让一家从构建里彻底消失，才需要删掉它的包或 EXCLUDE_AI_XXX。',
                  style: TextStyle(fontSize: 11, color: SemColors.textMuted, height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }

  /// 启停一家提供商：停用**当前正在用的那家**时先确认——AI 会立刻变成未配置。
  /// 提供商没有依赖，所以没有连带停用，只影响它自己。
  Future<void> _setProviderEnabled(AiProviderPlugin p, bool on) async {
    if (!on && _ai?.providerId == p.id) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('停用正在使用的提供商'),
          content: Text('「${p.label}」是当前选中的 AI 提供商。停用后它不再出现在「AI 设置」里，'
              'AI 识别按未配置处理（验证码退回手动输入、校历识别入口消失）。\n\n'
              '已填的 Key 会留着，重新启用就能继续用；也可以在「AI 设置」里先换一家。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('停用')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await _r.setProviderEnabled(p.id, on);
    if (!mounted) return;
    _toast(on ? '已启用「${p.label}」' : '已停用「${p.label}」');
  }

  /// 提供商：可停用（停用后不在 AI 设置里出现），当前选中的那家带「当前」标记。
  Widget _providerTile(AiProviderPlugin p) {
    final on = _r.isProviderEnabled(p.id);
    final cur = _ai?.providerId == p.id;
    return SwitchListTile(
      secondary: BrandLogo(asset: p.logo, initial: p.label),
      title: Row(
        children: [
          Flexible(
            child: Text(p.label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: cur ? FontWeight.w700 : FontWeight.w500,
                    color: on ? null : SemColors.textMuted)),
          ),
          if (cur) ...[
            const SizedBox(width: 6),
            Capsule('当前', color: on ? SemColors.accent : const Color(0xFF8A8F98)),
          ],
          if (!on) ...[
            const SizedBox(width: 6),
            const Capsule('已停用', color: Color(0xFF8A8F98)),
          ],
        ],
      ),
      subtitle: Text(p.description, style: const TextStyle(fontSize: 11.5)),
      value: on,
      onChanged: p.removable ? (v) => _setProviderEnabled(p, v) : null,
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

  /// AI 能力（提供方是 AI 设置插件）：宿主只按 id 取接口，不碰它包里的实现。
  /// 插件没装/被停用时取不到——那几处显示「未装 / 已停用」即可。
  AiCapability? get _ai => PluginRegistry.I.capability<AiCapability>(PluginIds.ai);

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
            '力导向布局：连线是引力——关联的插件互相吸引，越远引力越大；'
            '节点之间互相排斥，越近斥力越大；拖动节点松手后由物理规律决定去处。'
            '箭头指向被依赖的一方，实线 = 启停联动，长虚线 = 可选依赖，'
            '短虚线 = 工具卡片挂在工具中心。'
            '双指缩放 / 自由拖动视角，单指左右拖空白处也可平移（上下滑动留给页面）。',
            style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              // 力导向布局需要排布空间：按初始排布高度放宽些
              height: (layout.size.height * 1.2).clamp(240, 420).toDouble(),
              color: pluginGraphCanvasFill(),
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
