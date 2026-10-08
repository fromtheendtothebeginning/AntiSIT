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
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _ModelPickerDialog(
        models: models,
        current: _model.text.trim(),
        providerLabel: _c.provider.label,
        fetchError: fetchError,
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

  void _pickProvider(String id) {
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
                GlassDropdown<String>(
                  label: '提供商',
                  value: _c.providerId,
                  items: [
                    for (final it in aiProviders)
                      DropdownMenuItem(value: it.id, child: Text(it.label)),
                  ],
                  onChanged: (v) => v == null ? null : _pickProvider(v),
                ),
                const SizedBox(height: 4),
                Text(p.desc, style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _fetching ? null : _pickModel,
                      icon: _fetching
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.list_alt_outlined, size: 18),
                      label: Text(_fetching ? '拉取中…' : '选择模型'),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('用当前 Key 调 ${p.label} 的 /models 拉取列表后选择',
                          style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GlassField(
                  label: '模型 ID（上面选完会填到这里；也可手填）',
                  controller: _model,
                  prefixIcon: const Icon(Icons.memory_outlined),
                ),
                if (_model.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('当前模型：${_model.text.trim()}',
                      style: TextStyle(fontSize: 11.5, color: SemColors.textSecondary)),
                ],
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


/// 模型选择弹窗：列出官方 `/models` 拉到的模型（拉取失败则是缓存 ∪ 内置兜底列表）。
/// 顶部带筛选框——OpenAI 这类提供商的列表可能上百条，纯滚动不好找。
/// 样式跟全局一致：用主题里的对话框底（menuBg + 24 圆角），配色一律走 SemColors。
class _ModelPickerDialog extends StatefulWidget {
  const _ModelPickerDialog({
    required this.models,
    required this.current,
    required this.providerLabel,
    this.fetchError,
  });

  final List<String> models;
  final String current;
  final String providerLabel;
  final String? fetchError;

  @override
  State<_ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<_ModelPickerDialog> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 官方列表为准。当前选中的模型若不在列表里（如已下架 / 该 Key 无权限），
    // 单独提示一句——既不误导，也不硬塞回列表。
    final currentMissing =
        widget.current.isNotEmpty && !widget.models.contains(widget.current);
    final q = _filter.text.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.models
        : widget.models.where((m) => m.toLowerCase().contains(q)).toList();

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('选择模型')),
          Capsule(widget.providerLabel, color: SemColors.accent),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      content: SizedBox(
        width: 380,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.fetchError != null) ...[
              _note('拉取官方列表失败，下面是缓存 + 内置兜底列表：${widget.fetchError}',
                  SemColors.warning),
              const SizedBox(height: 10),
            ],
            if (currentMissing) ...[
              _note('当前模型 ${widget.current} 不在官方列表里（可能已下架或无权限），建议重新选择',
                  SemColors.warning),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _filter,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: '筛选模型名…',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              q.isEmpty ? '共 ${list.length} 个模型' : '匹配 ${list.length} / ${widget.models.length}',
              style: TextStyle(fontSize: 11, color: SemColors.textMuted),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text('没有匹配的模型',
                          style: TextStyle(fontSize: 13, color: SemColors.textMuted)))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final m = list[i];
                        final sel = m == widget.current;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(m,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: SemColors.textPrimary,
                                  fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
                          trailing: sel
                              ? Icon(Icons.check, size: 18, color: SemColors.accent)
                              : null,
                          onTap: () => Navigator.pop(context, m),
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

  Widget _note(String text, Color color) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: color, height: 1.5)),
      );
}
