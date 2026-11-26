import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:campus_core/campus_core.dart';

/// 取景框：圆角白框，中间透出相机画面。
class ScanWindow extends StatelessWidget {
  const ScanWindow({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 232,
        height: 232,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white70, width: 2),
        ),
      );
}

/// 扫码页底部的大按钮：实心（主操作）/ 描边（次操作）两态。
class ScanBigActionButton extends StatelessWidget {
  const ScanBigActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = false,
    this.busy = false,
  });

  final IconData? icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bg = filled ? Colors.white : Colors.black.withValues(alpha: 0.55);
    final fg = filled ? Colors.black87 : Colors.white;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white38),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
            else if (icon != null)
              Icon(icon, size: 22, color: fg),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// 多码选择面板：一张图片识出多个二维码时让用户挑一个。
class ScanCodePickerSheet extends StatelessWidget {
  const ScanCodePickerSheet({super.key, required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('识别到 ${codes.length} 个二维码，点选要用的一个',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: onSurface)),
            const SizedBox(height: 4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in codes)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.qr_code_2_rounded, size: 20),
                      title: Text(c,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, color: onSurface)),
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 二课签到面板：签到 / 签退方向由学校接口判定（报名码单向签到），
/// 按钮把学校的判定原文摆给用户看。
class ScanSignSheet extends StatefulWidget {
  const ScanSignSheet({
    super.key,
    required this.hdId,
    required this.hdActId,
    required this.raw,
    required this.submit,
    this.train = false,
  });

  final String hdId;
  final String hdActId;

  /// 原始二维码内容（复制 / 出问题时用户自己能核对）。
  final String raw;

  /// 报名（培训）码：另一个接口、单向签到，没有「签退」语义。
  final bool train;

  /// 提交签到，成功返回学校提示原文；失败抛 ApiError（学校原文）。
  final Future<String> Function() submit;

  @override
  State<ScanSignSheet> createState() => _ScanSignSheetState();
}

class _ScanSignSheetState extends State<ScanSignSheet> {
  bool _busy = false;
  String? _ok;
  String? _err;

  Future<void> _go() async {
    if (_busy || _ok != null) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final msg = await widget.submit();
      if (mounted) setState(() => _ok = msg.isEmpty ? '完成' : msg);
    } catch (e) {
      if (mounted) {
        setState(() => _err = e is ApiError ? e.message : '签到失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.train ? '第二课堂 · 报名签到' : '第二课堂 · 扫码签到',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: onSurface)),
            const SizedBox(height: 8),
            Text(
              _ok != null
                  ? '$_ok'
                  : (_err ??
                      (widget.train
                          ? '扫到的是第二课堂活动的报名（培训）签到码，点下方按钮完成签到。'
                          : '扫到的是第二课堂活动的签到码，点下方按钮提交，'
                              '由学校判定本次算签到还是签退。')),
              style: TextStyle(
                  fontSize: 14, height: 1.6,
                  color: _err != null ? SemColors.danger : onSurface),
            ),
            if (_ok == null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _go,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: _busy
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.how_to_reg_outlined, size: 20),
                label: Text(_busy ? '提交中…' : (widget.train ? '完成签到' : '完成签到 / 签退'),
                    style: const TextStyle(fontSize: 15)),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.raw));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('已复制码内容'),
                        behavior: SnackBarBehavior.floating));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('复制码内容'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('继续扫码'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 二课活动详情码面板：引导用户进 App 自己的活动详情页查看与报名。
class ScanDetailSheet extends StatelessWidget {
  const ScanDetailSheet({super.key, required this.raw, required this.onOpen});

  final String raw;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('第二课堂 · 活动码',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: onSurface)),
            const SizedBox(height: 8),
            Text('扫到的是第二课堂活动的详情码：点下方按钮查看活动介绍并报名，'
                '报名状态与提交都在 App 内完成。',
                style: TextStyle(fontSize: 14, height: 1.6, color: onSurface)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onOpen,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.event_note_outlined, size: 20),
              label: const Text('查看活动详情', style: TextStyle(fontSize: 15)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: raw));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('已复制码内容'),
                        behavior: SnackBarBehavior.floating));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('复制码内容'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('继续扫码'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 拓展模式的结果面板：网址 →「添加链接」，安装码 →「下载拓展」，
/// 第三方源 →「添加插件源」；点下去把 [ScanOutcome] 带回调用方。
class ScanExtensionSheet extends StatelessWidget {
  const ScanExtensionSheet({super.key, required this.outcome});

  final ScanOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final bundle = outcome is ScanBundleOutcome ? outcome as ScanBundleOutcome : null;
    final link = outcome is ScanLinkOutcome ? outcome as ScanLinkOutcome : null;
    final source = outcome is ScanSourceOutcome ? outcome as ScanSourceOutcome : null;
    final title = source != null
        ? '第三方插件源'
        : (bundle != null ? '拓展安装码' : '网址');
    final label = source != null
        ? '添加插件源'
        : (bundle != null ? '下载拓展' : '添加链接');
    final icon = source != null
        ? Icons.hub_outlined
        : (bundle != null ? Icons.download_rounded : Icons.add_link_rounded);
    final bg = source != null || bundle != null ? SemColors.accent : SemColors.success;
    final fg = source != null || bundle != null
        ? (SemColors.isDark ? SemColors.bg : Colors.white)
        : (SemColors.isDark ? Colors.black : Colors.white);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 10),
            if (source != null) ...[
              if (source.name != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    source.name!,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              SelectableText(source.repo,
                  style: TextStyle(
                      fontSize: 13, height: 1.5,
                      color: Theme.of(context).colorScheme.onSurface)),
              if (source.fingerprint != null) ...[
                const SizedBox(height: 4),
                Text('公钥指纹：${source.fingerprint}',
                    style: TextStyle(fontSize: 11.5, color: SemColors.textMuted)),
              ],
            ] else if (bundle != null) ...[
              if (bundle.name != null || bundle.id != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    [bundle.name, bundle.id].whereType<String>().join(' · '),
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              SelectableText(bundle.url,
                  style: TextStyle(
                      fontSize: 13, height: 1.5,
                      color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 4),
              Text('sha256：${bundle.sha256.substring(0, 16)}…',
                  style: TextStyle(fontSize: 11.5, color: SemColors.textMuted)),
            ] else
              SelectableText(link?.url ?? outcome.raw,
                  style: TextStyle(
                      fontSize: 13.5, height: 1.5,
                      color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: bg,
                  foregroundColor: fg,
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: () => Navigator.pop(context, outcome),
                icon: Icon(icon, size: 19),
                label: Text(label),
              ),
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: outcome.raw));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('已复制'),
                        behavior: SnackBarBehavior.floating));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('复制'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('继续扫码'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 通用扫码结果面板：内容可选可复制，网址可打开。
class ScanResultSheet extends StatelessWidget {
  const ScanResultSheet({super.key, required this.code, required this.onOpen});

  final String code;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(code);
    final isUrl = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('扫码结果',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 10),
            SelectableText(code,
                style: TextStyle(
                    fontSize: 14, height: 1.5,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('已复制'),
                        behavior: SnackBarBehavior.floating));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('复制'),
                ),
                if (isUrl)
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('打开链接'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('继续扫码'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
