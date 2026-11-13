import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:campus_core/campus_core.dart';

import 'backup_service.dart';

/// 备份与恢复：导出课表 / 设置 / 学校档案 / 插件偏好为 JSON，重装或换机后导入。
///
/// 账号密码、登录 token、直连 Cookie、AI Key 在 SecureStore 里，**不进入备份文件**；
/// 导入后需要重新登录。拓展（网页插件）及其数据也不在备份里。
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  String? _note;

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      final json = await BackupService.buildJson();
      final name = BackupService.fileName();
      if (Platform.isAndroid || Platform.isIOS) {
        // 移动端没有通用的“另存为”：写临时文件后交给系统分享面板，
        // 用户可存到「文件」/ 网盘，也可以直接发给自己。
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$name');
        await file.writeAsString(json, flush: true);
        await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'AntiSIT 备份',
        ));
        if (mounted) setState(() => _note = '备份已生成：$name（在分享面板里选择保存位置）');
      } else {
        final loc = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'AntiSIT 备份', extensions: ['json']),
          ],
        );
        if (loc == null) return;
        await File(loc.path).writeAsString(json, flush: true);
        if (mounted) setState(() => _note = '已导出到 ${loc.path}');
      }
    } catch (e) {
      if (mounted) showErr(context, e, title: '导出备份失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    XFile? picked;
    try {
      picked = await openFile(acceptedTypeGroups: const [
        XTypeGroup(label: 'AntiSIT 备份', extensions: ['json']),
      ]);
    } catch (e) {
      if (mounted) showErr(context, e, title: '打开文件选择器失败');
      return;
    }
    if (picked == null) return;

    BackupPreview preview;
    try {
      final bytes = await picked.readAsBytes();
      if (bytes.length > BackupService.maxBytes) {
        throw const FormatException('备份文件过大（超过 20 MB）');
      }
      preview = BackupService.parse(utf8.decode(bytes));
    } catch (e) {
      if (mounted) showErr(context, e, title: '备份文件无法读取');
      return;
    }

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入备份？'),
        content: Text(
          '${preview.summary}\n\n'
          '导入会覆盖本机同名的课表、设置、学校档案与插件偏好；未包含的本机数据保留。\n'
          '备份不含账号密码、登录 token、AI Key、直连 Cookie，导入后需要重新登录并按需填写。\n\n'
          '只导入你自己导出的备份。',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('覆盖导入')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await BackupService.apply(preview);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('导入完成'),
          content: const Text(
            '课表与设置已恢复。账号密码、AI Key、登录态不在备份中，请重新登录并按需填写。',
            style: TextStyle(height: 1.6),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('返回主页')),
          ],
        ),
      );
      if (!mounted) return;
      // 旧页面还握着导入前的课表/主题，整壳重建一次最干净。
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => hostShellBuilder()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) showErr(context, e, title: '导入备份失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          if (_busy) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 8),
          ],
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                ListTile(
                  enabled: !_busy,
                  leading: const Icon(Icons.upload_file_rounded),
                  title: const Text('导出备份'),
                  subtitle: const Text(
                    '课表、学期与作息、设置、学校档案、插件偏好；不含账号密码 / 登录态 / AI Key',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _export,
                ),
                const Divider(height: 1),
                ListTile(
                  enabled: !_busy,
                  leading: const Icon(Icons.download_rounded),
                  title: const Text('导入备份'),
                  subtitle: const Text(
                    '从 .json 备份恢复；会覆盖同名数据，导入后需要重新登录',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _import,
                ),
              ],
            ),
          ),
          if (_note != null) ...[
            const SizedBox(height: 10),
            Text(
              _note!,
              style: TextStyle(fontSize: 12, color: SemColors.textMuted, height: 1.5),
            ),
          ],
          const SizedBox(height: 12),
          const PageNotes(
            lines: [
              '备份文件是明文 JSON，请自己保管好；里面不含账号密码、登录 token、AI Key、直连 Cookie。',
              '拓展（网页插件）及其数据、课表自定义背景图不包含在备份里，需要重新添加 / 安装。',
              '导入会覆盖本机同名数据；账号与 AI 配置不在备份中，导入后请重新登录并按需填写。',
            ],
          ),
        ],
      ),
    );
  }
}
