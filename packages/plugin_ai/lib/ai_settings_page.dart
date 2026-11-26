import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:campus_core/campus_core.dart';

import 'ai_config.dart';
import 'ai_picker_dialog.dart';
import 'ai_vision.dart';

/// AI 设置：配置提供商、API Key 与模型，并测试连接。
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
    // 还没选过模型时先填该提供商的默认值
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

  /// 本页表单对应的配置草稿（调试 Key 不属于表单，原样带过去）。
  AiConfig get _draft => AiConfig(
        enabled: _c.enabled,
        providerId: _c.providerId,
        model: _model.text.trim(),
        customBaseUrl: _base.text.trim(),
        keys: Map<String, String>.from(_c.keys),
      )
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

  /// 选择模型：先用当前 Key 调官方 `/models` 拉真实可用列表，失败退回「缓存 ∪ 内置」；
  /// 不按模型名猜能否识图（实测能识图的模型名字里未必有 vision）。
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
      builder: (_) => AiPickerDialog(
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
        items: [for (final m in models) (value: m, title: m, leading: null)],
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
          _msg =
              '连接成功，模型回复：${out.length > 40 ? '${out.substring(0, 40)}…' : out}';
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

  /// 开发期临时 Key：写本机安全存储，不进仓库、release 不读。
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
            Text(
              '临时 Key 只存本机、不会被提交到仓库；release 构建完全不读它。清空即可移除。',
              style: TextStyle(
                fontSize: 12,
                color: SemColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Key',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
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

  /// 打开该提供商的开放平台；打不开浏览器就把链接复制给用户。
  Future<void> _openApplyPage(AiProviderPlugin p) async {
    try {
      await launchUrl(Uri.parse(p.docs), mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: p.docs));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('打不开浏览器，申请链接已复制'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 提供商选择：列表来自插件注册表，顺序 = 清单顺序。
  Future<void> _pickProviderDialog() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => AiPickerDialog(
        title: '选择提供商',
        current: _c.providerId,
        searchHint: null, // 十几个提供商，一屏看得完，不需要筛选
        items: [
          for (final p in PluginRegistry.I.providerChoices)
            (
              value: p.id,
              title: p.label,
              leading: BrandLogo(asset: p.logo, initial: p.label),
            ),
        ],
      ),
    );
    if (picked != null) _applyProvider(picked);
  }

  void _applyProvider(String id) {
    if (id == _c.providerId) return; // 重选当前提供商不该把已选好的模型重置掉
    final p = PluginRegistry.I.providerById(id);
    if (p == null) return; // 刚被删掉的包里点进来的旧列表：忽略
    _c.setApiKey(_key.text); // 先记住当前提供商的 Key
    setState(() {
      _c.providerId = id;
      _key.text = _c.apiKey; // 切到该提供商自己的 Key
      _model.text = p.defaultModel; // 换提供商时模型也用它的默认值
      _base.text = _c.customBaseUrl;
      _msg = null;
    });
  }

  /// 正在编辑的那家：按存档里的 id 取（已被停用也要显示），没装才退回解析结果。
  AiProviderPlugin get _shown =>
      PluginRegistry.I.providerById(_c.providerId) ?? _c.provider;

  /// 需要提醒的地方（当前提供商被停用 / 全都停用了），与底部 `_msg` 同一套配色。
  Widget _notice(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: SemColors.dangerSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style:
              TextStyle(fontSize: 11.5, color: SemColors.danger, height: 1.6),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = _shown;
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final topInset = glassTopInset(context);
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(context, title: const Text('AI 设置')),
          body: GlassFadedBody(
            barHeight: topInset,
            child: ListView(
            padding: EdgeInsets.fromLTRB(12, 8 + topInset, 12, 24),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.auto_awesome_outlined),
                      title: const Text('启用 AI 识别'),
                      value: _c.enabled,
                      onChanged: (v) => setState(() => _c.enabled = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_c.providerUsable) ...[
                      _notice(
                        PluginRegistry.I.providerChoices.isEmpty
                            ? '所有 AI 提供商都被停用了，AI 识别暂时不可用：去「插件管理 → AI 提供商」打开至少一家。'
                            : '当前选的「${p.label}」已被停用或没装进来，AI 识别暂时不可用：'
                                '在下面换一家，或去「插件管理 → AI 提供商」把它打开。',
                      ),
                      const SizedBox(height: 12),
                    ],
                    GlassPicker(
                      label: '提供商',
                      value: _c.providerUsable ? p.label : '${p.label}（已停用）',
                      prefixIcon: BrandLogo(asset: p.logo, initial: p.label),
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
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _openApplyPage(p),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: Text(p.applyLabel),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              Uri.tryParse(p.docs)?.host ?? p.docs,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: SemColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    GlassPicker(
                      label: '模型',
                      value: _model.text.trim(),
                      hint: '未选择',
                      prefixIcon: _fetching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.memory_outlined),
                      helperText: _fetching
                          ? '正在拉取 ${p.label} 的官方模型列表…'
                          : '点开用当前 Key 调 ${p.label} 的 /models 拉取后选择；列表里没有的模型可直接输入',
                      onTap: _busy || _fetching ? () {} : _pickModel,
                    ),
                    // 开发期临时 Key：只写本机安全存储，不进仓库；仅 debug 构建显示
                    if (kDebugMode) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.bug_report_outlined,
                            size: 14,
                            color: SemColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _c.debugApiKey.isEmpty
                                  ? '调试 Key：未设置（仅 debug 构建生效）'
                                  : '调试 Key：已设置 ${_maskKey(_c.debugApiKey)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: SemColors.textMuted,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _editDebugKey,
                            child: const Text(
                              '设置',
                              style: TextStyle(fontSize: 12),
                            ),
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
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.wifi_tethering, size: 18),
                          label: const Text('测试连接'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _busy ? null : _save,
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                    if (_msg != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _ok
                              ? SemColors.successSoft
                              : SemColors.dangerSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _msg!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _ok ? SemColors.success : SemColors.danger,
                            height: 1.5,
                          ),
                        ),
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
                    Text(
                      '能做些什么',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _bullet(
                      '自动识别验证码：直连登录教务/学工需要验证码时，AI 读图与手输框同时开始'
                      '（已关闭思考，只取几个字符）——你先输完就用你输的，AI 先认出来就自动提交；'
                      '识别失败或没配 AI 就纯手输。',
                    ),
                    _bullet('识别校历调休：在课表「调休设置」里选一张校历截图，AI 提取放假 / 调休上课日并写入规则。'),
                    _bullet('必须选支持读图的模型；换提供商后 Key 各自独立保存，不用重填。'),
                  ],
                ),
              ),
              // 从组件边上挪下来的说明，统一沉到页底
              const PageNotes(
                lines: ['Key 只保存在本机，直连模式下由 App 直接调用你填的 AI 服务（不经任何中转）。'],
              ),
            ],
          ),
          ),
        );
      },
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
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: SemColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: SemColors.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      );
}
