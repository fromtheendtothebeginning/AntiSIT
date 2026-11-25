import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';
import 'plugin_manager_dialogs.dart';
import 'plugin_manager_sections.dart';

/// 插件管理：功能插件的启停、主题切换与依赖关系可视化（停用会连带停掉依赖方）。
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

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(fontSize: 13)),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _setEnabled(FeaturePlugin p, bool on) async {
    if (on) {
      final turned = await _r.enable(p.id);
      if (!mounted || turned.isEmpty) return;
      final deps = turned.where((x) => x != p.id).toList();
      _toast(
        deps.isEmpty
            ? '已启用「${p.name}」'
            : '已启用「${p.name}」，并连带启用依赖：${deps.map((id) => pluginDisplayName(_r, id)).join('、')}',
      );
      return;
    }

    final gone = _r.disableClosure(p.id);
    if (gone.isNotEmpty) {
      final ok = await confirmCascadeDisable(context,
          pluginName: p.name,
          goneNames: gone.map((id) => pluginDisplayName(_r, id)).toList());
      if (!ok || !mounted) return;
    }
    // 有些插件关闭前要用户先过条款（风险提醒：关闭即自担风险），取消就不关。
    final guard = _r.capability<RiskNoticeCapability>(p.id);
    if (guard != null && !await guard.confirmDisable(context)) return;
    final off = await _r.disable(p.id);
    if (!mounted || off.isEmpty) return;
    _toast('已停用：${off.map((id) => pluginDisplayName(_r, id)).join('、')}');
  }

  Future<void> _setProviderEnabled(AiProviderPlugin p, bool on) async {
    if (!on && _ai?.providerId == p.id) {
      final ok = await confirmDisableActiveProvider(context, providerLabel: p.label);
      if (!ok || !mounted) return;
    }
    await _r.setProviderEnabled(p.id, on);
    if (!mounted) return;
    _toast(on ? '已启用「${p.label}」' : '已停用「${p.label}」');
  }

  /// AI 能力（提供方是 AI 设置插件）：宿主只按 id 取接口，插件没装 / 停用时为 null。
  AiCapability? get _ai =>
      PluginRegistry.I.capability<AiCapability>(PluginIds.ai);

  @override
  Widget build(BuildContext context) {
    // 整页监听：顶栏样式开关改完要连 Scaffold 一起重建
    return ListenableBuilder(
      listenable: Listenable.merge([_r, AppState.I]),
      builder: (context, _) {
        // 顶栏留白要在建 Scaffold 之前算（body 里的 MediaQuery 已被扣掉状态栏）
        final topInset = glassTopInset(context);
        return Scaffold(
          // 顶栏是悬浮玻璃条：内容从它底下穿过去，渐变模糊才有东西可糊
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(context, title: const Text('插件管理')),
          body: GlassFadedBody(
            barHeight: topInset,
            child: ListView(
            // 顶部让出悬浮顶栏
            padding: EdgeInsets.fromLTRB(12, 4 + topInset, 12, 24),
            children: [
              if (_r.problems.isNotEmpty) pluginProblemsCard(_r),
              pluginGraphCard(
                _r,
                selected: _selected,
                onSelected: (id) =>
                    setState(() => _selected = _selected == id ? null : id),
                onToggleFeature: _setEnabled,
              ),
              const SizedBox(height: 10),
              pluginEffectCard(_r, previewTab: _previewTab),
              const SizedBox(height: 10),
              pluginSectionTitle(
                '功能插件',
                '${_r.enabled.length}/${_r.features.length} 已启用',
              ),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [for (final p in _r.features) pluginFeatureTile(_r, p, onToggle: _setEnabled)],
                ),
              ),
              const SizedBox(height: 10),
              pluginSectionTitle('主题插件', '当前「${_r.theme.name}」'),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: const ThemePickerList(),
              ),
              const SizedBox(height: 10),
              pluginSectionTitle(
                'AI 提供商',
                '${_r.enabledProviders.length}/${_r.providers.length} 已启用 · '
                    '当前「${_ai?.providerLabel ?? '未装 / 已停用'}」',
              ),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [for (final p in _r.providerList) pluginProviderTile(_r, _ai, p, onToggle: _setProviderEnabled)],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(
                  '停用的提供商不会出现在「我的 → 设置 → AI 设置」的选择器里；'
                  '要让一家从构建里彻底消失，才需要删掉它的包或 EXCLUDE_AI_XXX。',
                  style: TextStyle(
                    fontSize: 11,
                    color: SemColors.textMuted,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}
