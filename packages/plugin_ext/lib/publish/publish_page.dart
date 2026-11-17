import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:campus_core/campus_core.dart';

import '../cordis_bundle.dart';
import '../workshop/workshop_store.dart';
import 'publish_models.dart';
import 'publish_service.dart';
import 'publish_settings.dart';

/// 「发布拓展」页：把工坊草稿推到 GitHub / Gitee，生成市场源与直装二维码。
///
/// Token 与签名私钥只进系统加密存储；页面只负责填表、进度和结果展示。
class PublishPage extends StatefulWidget {
  const PublishPage({
    super.key,
    required this.draft,
    this.workshop,
    this.service,
  });

  final WorkshopDraft draft;
  final WorkshopStore? workshop;
  final PublishService? service;

  @override
  State<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends State<PublishPage> {
  final _token = TextEditingController();
  final _repo = TextEditingController();
  final _branch = TextEditingController();

  PublishProvider _provider = PublishProvider.github;
  bool _obscure = true;
  bool _loading = true;
  bool _busy = false;
  String? _step;
  String? _error;
  String? _fingerprint;
  PublishResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _token.dispose();
    _repo.dispose();
    _branch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final config = await PublishSettings.loadConfig();
      final key = await PublishSettings.ensureKey();
      final provider = config?.provider ?? PublishProvider.github;
      final token = await PublishSettings.readToken(provider);
      if (!mounted) return;
      setState(() {
        _provider = provider;
        _repo.text = config?.repoInput ?? '';
        _branch.text = config?.branch ?? '';
        _token.text = token ?? '';
        _fingerprint = publishKeyFingerprint(key.publicKey);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取发布设置失败：$e';
      });
    }
  }

  Future<void> _switchProvider(PublishProvider provider) async {
    final token = await PublishSettings.readToken(provider);
    if (!mounted) return;
    setState(() {
      _provider = provider;
      _token.text = token ?? '';
      _error = null;
      _result = null;
    });
  }

  /// 校验并保存设置；失败返回 null（错误显示在页面上）。
  Future<PublishConfig?> _saveConfig({bool toast = true}) async {
    final PublishConfig config;
    try {
      config = PublishConfig.parse(
        provider: _provider,
        input: _repo.text,
        branch: _branch.text,
      );
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return null;
    }
    if (_token.text.trim().isEmpty) {
      setState(() => _error = '先填 ${_provider.label} 的 Personal Access Token');
      return null;
    }
    await PublishSettings.saveConfig(config);
    await PublishSettings.writeToken(_provider, _token.text);
    if (!mounted) return config;
    setState(() => _error = null);
    if (toast) _snack('设置已保存');
    return config;
  }

  Future<void> _publish() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _result = null;
    });
    final config = await _saveConfig(toast: false);
    if (config == null || !mounted) return;
    setState(() {
      _busy = true;
      _step = '准备…';
    });
    try {
      final service =
          widget.service ?? PublishService(workshop: widget.workshop);
      final result = await service.publish(
        draft: widget.draft,
        config: config,
        token: _token.text.trim(),
        onStep: (step) {
          if (mounted) setState(() => _step = step);
        },
        confirmCreateRepo: () => _confirmCreate(config),
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _fingerprint = result.fingerprint;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _step = null;
        });
      }
    }
  }

  Future<bool> _confirmCreate(PublishConfig config) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('新建仓库 ${config.owner}/${config.repo}？'),
        content: Text(
          '这个仓库还不存在。发布需要一个**公开**仓库，别人才能拉目录和拓展包。\n\n'
          '现在用你的 Token 新建它吗？会先初始化一个空 README。',
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('新建并发布')),
        ],
      ),
    );
    return ok == true;
  }

  static String _friendly(Object e) {
    if (e is FormatException) return e.message;
    if (e is StateError) return e.message;
    if (e is TimeoutException) return '请求超时，检查网络后重试';
    return '$e';
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _snack('已复制$label');
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.draft.manifest;
    return Scaffold(
      appBar: AppBar(
        title: const Text('发布拓展'),
        actions: [
          IconButton(
            tooltip: '保存设置',
            onPressed: _busy ? null : () => _saveConfig(),
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _header(m),
                const SizedBox(height: 14),
                SegmentedButton<PublishProvider>(
                  segments: [
                    for (final p in PublishProvider.values)
                      ButtonSegment(value: p, label: Text(p.label)),
                  ],
                  selected: {_provider},
                  onSelectionChanged:
                      _busy ? null : (s) => _switchProvider(s.first),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _token,
                  enabled: !_busy,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: '${_provider.label} Personal Access Token',
                    hintText: _provider == PublishProvider.github
                        ? 'ghp_… / github_pat_…'
                        : '在 Gitee 设置里生成',
                    helperText: '只存系统加密存储；'
                        '${_provider == PublishProvider.github ? '需要 public_repo 或 repo 权限' : '需要 projects 权限'}',
                    helperMaxLines: 2,
                    suffixIcon: IconButton(
                      tooltip: _obscure ? '显示' : '隐藏',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _copy(_provider.tokenUrl, 'Token 申请地址'),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: Text('复制 ${_provider.label} Token 申请地址',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _repo,
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '仓库',
                    hintText: 'yourname/antisit-plugins',
                    helperText: '仓库必须公开；会维护 ext/、dist/、market.json 与签名',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _branch,
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '分支（可空）',
                    hintText: '留空 = 仓库默认分支',
                  ),
                ),
                const SizedBox(height: 14),
                _fingerprintCard(),
                const SizedBox(height: 16),
                if (_busy) ...[
                  const LinearProgressIndicator(minHeight: 3),
                  const SizedBox(height: 8),
                  Text(_step ?? '发布中…',
                      style: TextStyle(fontSize: 12.5, color: SemColors.textMuted)),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed: _busy ? null : _publish,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text('发布到 ${_provider.label}'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _errorCard(_error!),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 18),
                  _ResultCard(
                    result: _result!,
                    onCopy: _copy,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _header(CordisManifest m) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SemColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SemColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${m.name}  v${m.version}',
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(m.id, style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
            const SizedBox(height: 8),
            Text(
              m.permissions.isEmpty
                  ? '权限：无'
                  : '权限：${m.permissions.join(' / ')}',
              style: TextStyle(fontSize: 12, color: SemColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              '发布后：别人扫结果页的二维码可直接安装；把源地址加到市场就能接收后续更新。',
              style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 4),
            Text(
              '发布密钥只存在本机加密存储：清除 App 数据 / 换机后指纹会变，别人需要重新添加源。',
              style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.5),
            ),
          ],
        ),
      );

  Widget _fingerprintCard() => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: SemColors.cardElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('发布公钥指纹',
                      style: TextStyle(fontSize: 11.5, color: SemColors.textMuted)),
                  const SizedBox(height: 2),
                  SelectableText(
                    _fingerprint ?? '生成中…',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.6),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '复制指纹',
              onPressed: _fingerprint == null
                  ? null
                  : () => _copy(_fingerprint!, '公钥指纹'),
              icon: const Icon(Icons.copy_rounded, size: 18),
            ),
          ],
        ),
      );

  Widget _errorCard(String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SemColors.dangerSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          text,
          style: TextStyle(fontSize: 12.5, height: 1.5, color: SemColors.danger),
        ),
      );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.onCopy});

  final PublishResult result;
  final Future<void> Function(String text, String label) onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SemColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SemColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: SemColors.success, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('已发布「${result.name}」v${result.version}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('别人用 AntiSIT「拓展 → 扫一扫」扫下面这张码即可下载安装。',
              style: TextStyle(fontSize: 12, color: SemColors.textMuted, height: 1.5)),
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: QrImageView(
                data: result.installCode,
                size: 220,
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _row('源地址', result.sourceInput),
          const SizedBox(height: 6),
          _row('分支', result.branch),
          const SizedBox(height: 6),
          _row('公钥指纹', result.fingerprint),
          const SizedBox(height: 12),
          Text(
            '想接收后续更新：在「拓展 → 市场 → 添加第三方源」填上面的源地址，'
            '核对指纹后添加；以后你重新发布，他们就能在列表里一键更新。',
            style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.55),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => onCopy(result.sourceInput, '源地址'),
                child: const Text('复制源地址'),
              ),
              OutlinedButton(
                onPressed: () => onCopy(result.installCode, '安装码'),
                child: const Text('复制安装码'),
              ),
              OutlinedButton(
                onPressed: () => onCopy(result.shareText, '分享文案'),
                child: const Text('复制分享文案'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
          const SizedBox(height: 2),
          SelectableText(value,
              style: const TextStyle(fontSize: 12.5, height: 1.45)),
        ],
      );
}
