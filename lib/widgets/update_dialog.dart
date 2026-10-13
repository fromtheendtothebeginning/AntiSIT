import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../update_check.dart';

/// 引导更新弹窗：说清「当前 → 最新」、列出变更清单，给「去下载」和「稍后」两个出口。
/// 启动时查到新版本、或手动检查后查到，都由调用方弹出。
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('发现新版本 ${info.version}'),
      content: Column(
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
      actions: [
        TextButton(
          onPressed: () {
            UpdateChecker.I.skip(); // 记下这个版本，之后不再自动弹
            Navigator.pop(ctx);
          },
          child: const Text('稍后'),
        ),
        FilledButton.icon(
          // 有安装包直链就直接下 APK；没有就退到发布页（页面里也有下载链接）
          onPressed: () => openExternalUrl(ctx, info.apkUrl ?? info.pageUrl),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('去下载'),
        ),
      ],
    ),
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
