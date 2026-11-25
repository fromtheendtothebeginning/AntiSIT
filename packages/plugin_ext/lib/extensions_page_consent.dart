import 'package:flutter/material.dart';

import 'ext_consent.dart';
import 'extension_item.dart';
import 'ext_permissions.dart';

/// 权限管理弹窗：静态权限只读展示，运行时授权逐项开关。
///
/// 关闭某能力后，插件下次用到会重新询问或直接被拒；弹窗通知会立即停止。
Future<void> manageExtensionConsent(
  BuildContext context,
  ExtensionItem e, {
  required void Function(String message) toast,
}) async {
  final grants = await ExtConsentService.I.grants(e.id);
  if (!context.mounted) return;
  final staticLabels = describeSensitivePermissions(e.permissions);
  final caps = <String>{
    if (e.permissions.contains('notification')) 'notification.popup',
    if (e.permissions.contains('clipboard')) 'clipboard.read',
    if (e.permissions.contains('background')) 'background.keepalive',
    ...grants.keys,
  }.toList()..sort();
  final state = <String, bool?>{for (final cap in caps) cap: grants[cap]};
  final reset = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        title: Text('「${e.name}」的权限'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (staticLabels.isNotEmpty) ...[
                  const Text(
                    '安装时声明（只读）',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final label in staticLabels)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                ],
                const Text(
                  '运行时授权',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (caps.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '这个拓展没有需要单独确认的能力。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                for (final cap in caps)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(ExtConsentService.describe(cap)),
                    subtitle: Text(
                      state[cap] == true
                          ? '已允许'
                          : (state[cap] == false ? '已拒绝' : '未申请；插件用到时会询问'),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    value: state[cap] == true,
                    onChanged: (value) async {
                      if (value) {
                        await ExtConsentService.I.allow(e.id, cap);
                      } else {
                        await ExtConsentService.I.deny(e.id, cap);
                      }
                      setDialog(() => state[cap] = value);
                    },
                  ),
                const SizedBox(height: 6),
                const Text(
                  '关闭后，插件下次用到这项能力会重新询问或直接拒绝；'
                  '弹窗通知会立即停止。',
                  style: TextStyle(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('关闭'),
          ),
          if (caps.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('全部重置'),
            ),
        ],
      ),
    ),
  );
  if (reset == true) {
    await ExtConsentService.I.revokeAll(e.id);
    toast('已重置「${e.name}」的运行时授权');
  }
}
