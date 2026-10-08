import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ai/ai_settings.dart';
import '../ai/ai_vision.dart';
import '../api_error.dart';
import '../widgets/common.dart';

/// AI 设置：直连模式下 App 自己调用户的 AI 服务，用于
/// ① 自动识别登录验证码；② 识别校历图片里的调休安排。
/// 参数与网站在「我的 → AI 设置」里配的是同一套（提供商 / Key / 模型 / 自定义地址）。
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
  String? _msg;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _c = AiVision.I.config.copy();
    _key.text = _c.apiKey;
    _model.text = _c.model;
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
        apiKey: _key.text,
        model: _model.text.trim(),
        customBaseUrl: _base.text.trim(),
      )
        // 调试 Key 不属于本页表单，但要原样带过去——否则保存草稿时会被冲掉
        ..debugApiKey = _c.debugApiKey;

  Future<void> _save() async {
    await AiVision.I.save(_draft);
    if (!mounted) return;
    setState(() {
      _msg = '已保存';
      _ok = true;
    });
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      // 测试用当前草稿值（不必先保存）
      final saved = AiVision.I.config;
      await AiVision.I.save(_draft);
      try {
        final out = await AiVision.I.testConnection();
        if (mounted) {
          setState(() {
            _msg = '连接成功，模型回复：${out.length > 40 ? '${out.substring(0, 40)}…' : out}';
            _ok = true;
          });
        }
      } finally {
        // 测试只验证参数，不替用户决定是否启用
        await AiVision.I.save(saved);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = e is ApiError ? e.message : e.toString();
          _ok = false;
        });
      }
    } finally {
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
            Text('临时 Key 只存本机、不会被提交到仓库；release 构建完全不读它。'
                '清空即可移除。',
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
    final p = aiProviderById(id)!;
    setState(() {
      _c.providerId = id;
      // 换提供商时把模型切到该提供商默认值，避免留着上一个提供商的模型名
      _model.text = p.defaultModel;
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
                Text(
                  'Key 只保存在本机，直连模式下由 App 直接调用你填的 AI 服务（不经任何中转）。',
                  style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6),
                ),
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
                      DropdownMenuItem(
                        value: it.id,
                        child: Text('${it.label} · ${it.desc}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => v == null ? null : _pickProvider(v),
                ),
                const SizedBox(height: 14),
                GlassField(
                  label: 'API Key',
                  controller: _key,
                  obscureText: true,
                  prefixIcon: const Icon(Icons.key_outlined),
                  hintText: '粘贴你的 API Key',
                ),
                const SizedBox(height: 14),
                GlassDropdown<String>(
                  label: p.models.isEmpty ? '模型（自定义提供商请直接填）' : '识图模型',
                  value: p.models.contains(_model.text) ? _model.text : null,
                  items: [
                    for (final m in p.models) DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _model.text = v);
                  },
                ),
                const SizedBox(height: 10),
                GlassField(
                  label: '模型 ID（可手填，如 glm-4.6 / gpt-4o）',
                  controller: _model,
                  prefixIcon: const Icon(Icons.memory_outlined),
                ),
                if (p.models.isEmpty) ...[
                  const SizedBox(height: 6),
                  Text('该提供商没有内置模型列表，请直接填模型 ID。',
                      style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                ],
                const SizedBox(height: 14),
                GlassField(
                  label: p.needsBaseUrl
                      ? 'Base URL（必填，OpenAI 兼容地址）'
                      : 'Base URL（留空用默认：${p.baseUrl}）',
                  controller: _base,
                  prefixIcon: const Icon(Icons.link_outlined),
                  hintText: p.baseUrl.isEmpty ? 'https://your-host/v1' : p.baseUrl,
                ),
                if (p.docs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText('申请 Key：${p.docs}',
                      style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
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
                const SizedBox(height: 14),
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
                      color: _ok ? SemColors.successSoft : SemColors.dangerSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_msg!,
                        style: TextStyle(
                            fontSize: 12, color: _ok ? SemColors.success : SemColors.danger, height: 1.5)),
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
                _bullet('自动识别验证码：直连登录教务/学工需要验证码时，先让 AI 读图；识别失败或没配 AI 就回退到手输。'),
                _bullet('识别校历调休：在课表「调休设置」里选一张校历截图，AI 提取放假 / 调休上课日并写入规则。'),
                _bullet('识别效果取决于模型是否支持读图；推理型模型建议开启思考更稳，但会慢一些。'),
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
