import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../update_check.dart';
import '../update_download.dart';

/// 引导更新弹窗：说清「当前 → 最新」、列出变更清单。有安装包直链时支持**应用内
/// 下载**（进度条 + sha256 校验，见 [UpdateDownloader]），完成拉起系统安装器；
/// 下载失败随时可重试或退回浏览器打开链接。启动时查到新版本、或手动检查后查到，
/// 都由调用方弹出。
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('发现新版本 ${info.version}'),
      content: ListenableBuilder(
        listenable: UpdateDownloader.I,
        builder: (ctx, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前 v${UpdateChecker.I.current} · 最新 v${info.version}',
                style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
            const SizedBox(height: 6),
            Text('下载 APK 覆盖安装即可（登录态与课表数据保留；装过其它签名版本的需先卸载）',
                style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.5)),
            if (info.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(
                  child: Text(info.notes,
                      style: const TextStyle(fontSize: 12.5, height: 1.7)),
                ),
              ),
            ],
            ..._downloadArea(ctx, info),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => openExternalUrl(ctx, info.pageUrl),
                child: Text('查看发布页',
                    style: TextStyle(fontSize: 12, color: SemColors.accent)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            // 下载到一半走人：掐掉连接、删掉半截文件（已下完的不动，回来还能装）
            if (UpdateDownloader.I.busy) UpdateDownloader.I.cancel();
            UpdateChecker.I.skip(); // 记下这个版本，之后不再自动弹
            Navigator.pop(ctx);
          },
          child: const Text('稍后'),
        ),
        _mainAction(ctx, info),
      ],
    ),
  );
}

/// 弹窗内容里的下载区：进度条 / 校验中 / 失败原因与兜底入口。
List<Widget> _downloadArea(BuildContext ctx, UpdateInfo info) {
  final d = UpdateDownloader.I;
  if (info.apkUrl == null) return const [];
  switch (d.status) {
    case 'downloading':
      return [
        const SizedBox(height: 12),
        LinearProgressIndicator(value: d.total > 0 ? d.received / d.total : null),
        const SizedBox(height: 4),
        Text(_progressText(d),
            style: TextStyle(fontSize: 11.5, color: SemColors.textMuted)),
      ];
    case 'verifying':
      return [
        const SizedBox(height: 12),
        Row(children: [
          const SizedBox(
              width: 12, height: 12,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text('校验安装包…', style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
        ]),
      ];
    default:
      return [
        if (d.error != null) ...[
          const SizedBox(height: 8),
          Text(d.error!, style: TextStyle(fontSize: 12, color: SemColors.danger)),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () => openExternalUrl(ctx, info.apkUrl!),
            child: Text('用浏览器打开下载链接',
                style: TextStyle(fontSize: 12, color: SemColors.accent)),
          ),
        ],
        if (d.installNote != null) ...[
          const SizedBox(height: 8),
          Text(d.installNote!, style: TextStyle(fontSize: 12, color: SemColors.accent)),
        ],
      ];
  }
}

String _progressText(UpdateDownloader d) {
  String mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';
  return d.total > 0 ? '${mb(d.received)} / ${mb(d.total)}' : '已下载 ${mb(d.received)}';
}

/// 主按钮跟着下载状态走：去下载 → 下载中（不可点）→ 安装 / 重试。
Widget _mainAction(BuildContext ctx, UpdateInfo info) {
  // 没挂安装包直链：只能去发布页（页面里有下载入口）
  if (info.apkUrl == null) {
    return FilledButton.icon(
      onPressed: () => openExternalUrl(ctx, info.pageUrl),
      icon: const Icon(Icons.download_rounded, size: 18),
      label: const Text('去下载'),
    );
  }
  return ListenableBuilder(
    listenable: UpdateDownloader.I,
    builder: (ctx, _) {
      final d = UpdateDownloader.I;
      switch (d.status) {
        case 'downloading' || 'verifying':
          return FilledButton.icon(
            onPressed: null,
            icon: const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            label: Text(d.status == 'downloading' ? '下载中' : '校验中'),
          );
        case 'ready':
          return FilledButton.icon(
            onPressed: () => d.install(),
            icon: const Icon(Icons.install_mobile_rounded, size: 18),
            label: const Text('安装'),
          );
        case 'error':
          return FilledButton.icon(
            onPressed: () => d.start(info),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('重试'),
          );
        default:
          return FilledButton.icon(
            onPressed: () => d.start(info),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('去下载'),
          );
      }
    },
  );
}

/// 打开外部链接；失败（没有浏览器 / 平台不支持）则复制链接并提示，
/// 与「我的」页打开协议原文同一套兜底。
Future<void> openExternalUrl(BuildContext context, String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('已复制下载链接，可粘贴到浏览器打开'),
        behavior: SnackBarBehavior.floating));
  }
}
