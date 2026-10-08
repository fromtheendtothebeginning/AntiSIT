import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ai/ai_settings.dart';
import '../ai/ai_vision.dart';
import '../api_error.dart';
import '../widgets/common.dart';

/// AI 设置：直连模式下 App 自己调用户的 AI 服务，用于
/// ① 自动识别登录验证码（关思考，只要几个字符）；② 识别校历图片里的调休安排。
/// 模型选择：用 Key 调 `GET {base}/models` 拉真实可用模型（失败回退「缓存 ∪ 内置列表」），
/// 再弹窗让用户挑一个——不按模型名猜能否识图（实测 deepseek-flash 能识图但没有 vision 字样）。
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  late AiConfig _c;
  final _key = TextEditingController();
  final _model = TextEditingController();
  final _base = TextEditingController();

  bool _busy = false;
  bool _fetching = false;
  String? _msg;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _c = AiVision.I.config.copy();
    _key.text = _c.apiKey;
    // 还没选过模型时先填该提供商的默认值；用户可随时点「选择模型」换成别的
    _model.text = _c.model.isNotEmpty ? _c.model : _c.provider.defaultModel;
    _base.text = _c.customBaseUrl;
  }

  @override
  void dispose() {
    for (final c in [_key, _model, _base]) {
      c.dispose();
    }
    super.dispose();
  }

  AiConfig get _draft => AiConfig(
        enabled: _c.enabled,
        providerId: _c.providerId,
        model: _model.text.trim(),
        customBaseUrl: _base.text.trim(),
        keys: Map<String, String>.from(_c.keys),
      )
        // 调试 Key 不属于本页表单，但要原样带过去——否则保存草稿时会被冲掉
        ..debugApiKey = _c.debugApiKey;

  Future<void> _save() async {
    _c.setApiKey(_key.text);
    await AiVision.I.save(_draft);
    if (!mounted) return;
    setState(() {
      _msg = '已保存';
      _ok = true;
    });
  }

  /// 选择模型：先用当前 Key 调官方 `/models` 拉真实可用列表，再弹窗让用户挑一个。
  /// 拉取失败就退回「上次缓存 ∪ 注册表内置」，并在弹窗里说明原因——不让用户卡住。
  /// 不用「按模型名猜能否识图」那套：实测 deepseek-flash 能识图但名字里没有 vision，
  /// 猜错反而把能用的模型筛掉了。
  Future<void> _pickModel() async {
    _c.setApiKey(_key.text);
    setState(() {
      _fetching = true;
      _msg = null;
    });
    List<String> models = const [];
    String? fetchError;
    try {
      models = await AiVision.I.listModels(cfg: _draft);
    } catch (e) {
      fetchError = e is ApiError ? e.message : '$e';
      models = AiVision.I.selectableModels(); // 缓存 ∪ 内置
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
    if (!mounted) return;
    if (models.isEmpty) {
      setState(() {
        _msg = fetchError ?? '该提供商没有返回可用模型，请检查 Key / Base URL';
        _ok = false;
      });
      return;
    }
    final cur = _model.text.trim();
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _PickerDialog(
        title: '选择模型',
        badge: _c.provider.label,
        current: cur,
        searchHint: '筛选或直接输入模型 ID…',
        allowCustom: true,
        notes: [
          if (fetchError != null) '拉取官方列表失败，下面是缓存 + 内置兜底列表：$fetchError',
          if (cur.isNotEmpty && !models.contains(cur))
            '当前模型 $cur 不在官方列表里（可能已下架或无权限），建议重新选择',
        ],
        items: [for (final m in models) (value: m, title: m, subtitle: null, leading: null)],
      ),
    );
    if (picked != null && mounted) setState(() => _model.text = picked);
  }

  Future<void> _test() async {
    _c.setApiKey(_key.text);
    setState(() {
      _busy = true;
      _msg = null;
    });
    final saved = AiVision.I.config;
    try {
      await AiVision.I.save(_draft);
      final out = await AiVision.I.testConnection();
      if (mounted) {
        setState(() {
          _msg = '连接成功，模型回复：${out.length > 40 ? '${out.substring(0, 40)}…' : out}';
          _ok = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = e is ApiError ? e.message : e.toString();
          _ok = false;
        });
      }
    } finally {
      // 测试只验证参数，不替用户决定是否启用
      await AiVision.I.save(saved);
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 调试 Key 只露头尾，避免整串 key 出现在屏幕/截图里。
  static String _maskKey(String k) {
    final s = k.trim();
    if (s.length <= 10) return '****';
    return '${s.substring(0, 6)}…${s.substring(s.length - 4)}';
  }

  /// 开发期临时 Key：写本机 prefs（`ai_debug_api_key`），不进仓库、release 不读。
  Future<void> _editDebugKey() async {
    final ctrl = TextEditingController(text: _c.debugApiKey);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('调试 Key（仅 debug 构建）'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('临时 Key 只存本机、不会被提交到仓库；release 构建完全不读它。清空即可移除。',
                style: TextStyle(fontSize: 12, color: SemColors.textSecondary, height: 1.5)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'API Key', isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) {
      ctrl.dispose();
      return;
    }
    _c.debugApiKey = ctrl.text.trim();
    ctrl.dispose();
    await AiVision.I.save(_c, touchDebugKey: true);
    if (!mounted) return;
    setState(() {
      _msg = _c.debugApiKey.isEmpty ? '已清除调试 Key' : '调试 Key 已保存（仅本机）';
      _ok = true;
    });
  }

  /// 提供商也用同一个选择弹窗（与模型选择统一形态）。
  Future<void> _pickProviderDialog() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _PickerDialog(
        title: '选择提供商',
        current: _c.providerId,
        searchHint: null, // 提供商就 9 个，不需要筛选
        items: [
          for (final p in aiProviders)
            (
              value: p.id,
              title: p.label,
              subtitle: p.desc,
              leading: BrandLogo(asset: p.logo, initial: p.label),
            ),
        ],
      ),
    );
    if (picked != null) _applyProvider(picked);
  }

  void _applyProvider(String id) {
    if (id == _c.providerId) return; // 重选当前提供商不该把已选好的模型重置掉
    _c.setApiKey(_key.text); // 先记住当前提供商的 Key
    final p = aiProviderById(id)!;
    setState(() {
      _c.providerId = id;
      _key.text = _c.apiKey; // 切到该提供商自己的 Key
      _model.text = p.defaultModel; // 换提供商时模型也用它的默认值
      _base.text = _c.customBaseUrl;
      _msg = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _c.provider;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('启用 AI 识别'),
                  subtitle: const Text('自动识别登录验证码、识别校历图片里的调休',
                      style: TextStyle(fontSize: 12)),
                  value: _c.enabled,
                  onChanged: (v) => setState(() => _c.enabled = v),
                ),
                Text('Key 只保存在本机，直连模式下由 App 直接调用你填的 AI 服务（不经任何中转）。',
                    style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassPicker(
                  label: '提供商',
                  value: p.label,
                  prefixIcon: BrandLogo(asset: p.logo, initial: p.label),
                  helperText: p.desc,
                  onTap: _busy || _fetching ? () {} : _pickProviderDialog,
                ),
                const SizedBox(height: 14),
                GlassField(
                  label: 'API Key（按提供商分别保存）',
                  controller: _key,
                  obscureText: true,
                  prefixIcon: const Icon(Icons.key_outlined),
                  hintText: '粘贴 ${p.label} 的 API Key',
                ),
                if (p.isCustom) ...[
                  const SizedBox(height: 14),
                  GlassField(
                    label: 'Base URL（OpenAI 兼容地址，必填）',
                    controller: _base,
                    prefixIcon: const Icon(Icons.link_outlined),
                    hintText: 'https://your-host/v1',
                  ),
                ],
                if (p.docs.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SelectableText('申请 Key：${p.docs}',
                      style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                ],
                const SizedBox(height: 14),
                GlassPicker(
                  label: '模型',
                  value: _model.text.trim(),
                  hint: '未选择',
                  prefixIcon: _fetching
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.memory_outlined),
                  helperText: _fetching
                      ? '正在拉取 ${p.label} 的官方模型列表…'
                      : '点开用当前 Key 调 ${p.label} 的 /models 拉取后选择；列表里没有的模型可直接输入',
                  onTap: _busy || _fetching ? () {} : _pickModel,
                ),
                // 开发期临时 Key：只写本机 prefs，不进仓库；仅 debug 构建显示
                if (kDebugMode) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.bug_report_outlined, size: 14, color: SemColors.textMuted),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _c.debugApiKey.isEmpty
                              ? '调试 Key：未设置（仅 debug 构建生效）'
                              : '调试 Key：已设置 ${_maskKey(_c.debugApiKey)}',
                          style: TextStyle(fontSize: 11, color: SemColors.textMuted),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _editDebugKey,
                        child: const Text('设置', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _test,
                      icon: _busy
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.wifi_tethering, size: 18),
                      label: const Text('测试连接'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(onPressed: _busy ? null : _save, child: const Text('保存')),
                  ],
                ),
                if (_msg != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _ok ? SemColors.successSoft : SemColors.dangerSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_msg!,
                        style: TextStyle(
                            fontSize: 12,
                            color: _ok ? SemColors.success : SemColors.danger,
                            height: 1.5)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('能做些什么', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _bullet('自动识别验证码：直连登录教务/学工需要验证码时，先让 AI 读图（已关闭思考，只取几个字符）；'
                    '识别失败或没配 AI 就回退到手输。'),
                _bullet('识别校历调休：在课表「调休设置」里选一张校历截图，AI 提取放假 / 调休上课日并写入规则。'),
                _bullet('必须选支持读图的模型；换提供商后 Key 各自独立保存，不用重填。'),
                const SizedBox(height: 2),
                Text('提供商图标取自 simple-icons（CC0）与 Iconify 的品牌集合，「自定义」为自绘插头图标；'
                    '均按主题单色着色。',
                    style: TextStyle(fontSize: 11, color: SemColors.textMuted, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Container(
                width: 5, height: 5,
                decoration: BoxDecoration(color: SemColors.accent, shape: BoxShape.circle),
              ),
            ),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 12, color: SemColors.textSecondary, height: 1.6)),
            ),
          ],
        ),
      );
}



// ==================== 统一的选择弹窗（提供商 / 模型共用） ====================

typedef _PickerItem = ({String value, String title, String? subtitle, Widget? leading});

/// 通用选择弹窗：提供商与模型共用同一形态，避免两处入口风格不一致。
/// 样式走全局：主题对话框底（menuBg + 24 圆角）、Capsule 徽章标题、SemColors 配色。
class _PickerDialog extends StatefulWidget {
  const _PickerDialog({
    required this.title,
    required this.items,
    required this.current,
    this.badge,
    this.notes = const [],
    this.searchHint,
    this.allowCustom = false,
  });

  final String title;
  final List<_PickerItem> items;
  final String? current;

  /// 右上角徽章（如提供商标识）。
  final String? badge;

  /// 需要额外说明的提示（拉取失败、当前值已失效等），用告警色。
  final List<String> notes;

  /// 非空时显示筛选框（长列表才好找）。
  final String? searchHint;

  /// 允许把筛选框里输入的任意字符串当作结果返回（用于手填模型 ID）。
  final bool allowCustom;

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final raw = _filter.text.trim();
    final q = raw.toLowerCase();
    final list = q.isEmpty
        ? widget.items
        : widget.items
            .where((it) => it.title.toLowerCase().contains(q) ||
                (it.subtitle ?? '').toLowerCase().contains(q))
            .toList();
    // 允许手填时：筛选框里输入的内容若不是现成项，置顶一条「使用 …」
    final custom = widget.allowCustom && raw.isNotEmpty && !widget.items.any((it) => it.value == raw);

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          if (widget.badge != null) Capsule(widget.badge!, color: SemColors.accent),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      content: SizedBox(
        width: 380,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final note in widget.notes) ...[
              _note(note),
              const SizedBox(height: 8),
            ],
            if (widget.searchHint != null) ...[
              TextField(
                controller: _filter,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                q.isEmpty
                    ? '共 ${list.length} 项'
                    : '匹配 ${list.length} / ${widget.items.length}',
                style: TextStyle(fontSize: 11, color: SemColors.textMuted),
              ),
              const SizedBox(height: 2),
            ],
            Expanded(
              // 列表为空但有「使用输入值」这条时也要渲染，否则手填入口会消失
              child: (list.isEmpty && !custom)
                  ? Center(
                      child: Text('没有匹配的项',
                          style: TextStyle(fontSize: 13, color: SemColors.textMuted)))
                  : ListView.builder(
                      itemCount: list.length + (custom ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (custom && i == 0) {
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_outlined, size: 18, color: SemColors.accent),
                            title: Text('使用「$raw」',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: SemColors.accent,
                                    fontWeight: FontWeight.w600)),
                            onTap: () => Navigator.pop(context, raw),
                          );
                        }
                        final it = list[custom ? i - 1 : i];
                        final sel = it.value == widget.current;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: it.leading,
                          title: Text(it.title,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: SemColors.textPrimary,
                                  fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
                          subtitle: it.subtitle == null
                              ? null
                              : Text(it.subtitle!,
                                  style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                          trailing: sel
                              ? Icon(Icons.check, size: 18, color: SemColors.accent)
                              : null,
                          onTap: () => Navigator.pop(context, it.value),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      ],
    );
  }

  Widget _note(String text) {
    final color = SemColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color, height: 1.5)),
    );
  }
}
