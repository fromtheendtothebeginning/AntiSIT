import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';
import 'package:file_selector/file_selector.dart';

import 'bundle_import.dart';
import 'cordis_bundle.dart';
import 'extension_item.dart';
import 'extension_store.dart';
import 'extensions_page_dialogs.dart';
import 'ext_permissions.dart';
import 'scanned_install.dart';

/// 导入压缩包：选 zip → 解压到本地 → 让用户确认名称/简介/图标 → 入列。
Future<void> importExtensionBundle({
  required BuildContext context,
  required ExtensionStore store,
  required void Function(String message) toast,
}) async {
  XFile? picked;
  try {
    picked = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: '拓展压缩包', extensions: ['zip']),
      ],
    );
  } catch (e) {
    toast('打开文件选择器失败：$e');
    return;
  }
  if (picked == null) return;

  final bytes = await picked.readAsBytes();
  final CordisManifest manifest;
  try {
    manifest = readBundleManifest(bytes);
  } on FormatException catch (e) {
    toast(e.message);
    return;
  } catch (e) {
    toast('读取压缩包失败：$e');
    return;
  }
  if (store.items.any((e) => e.id == manifest.id)) {
    toast('已存在 id 为「${manifest.id}」的拓展，请先删除或让作者换一个 id');
    return;
  }

  ExtBundle bundle;
  try {
    bundle = extractBundle(
      bytes: bytes,
      dir: await store.bundleDir(manifest.id),
    );
  } on FormatException catch (e) {
    toast(e.message);
    return;
  } catch (e) {
    toast('解压失败：$e');
    return;
  }
  if (!context.mounted) return;

  // 清单已经带了名称 / 简介 / 权限，导入后仍让用户确认卡片显示值。
  final preset = ExtensionItem(
    id: manifest.id,
    name: manifest.name,
    url: bundle.entry,
    desc: manifest.desc,
    bundled: true,
    runtime: ExtensionItem.runtimeCordis,
    version: manifest.version,
    permissions: manifest.permissions,
    // 压缩包同样是别人给的代码：走权限门（确认弹窗里列的权限要真的执行）
    permissionsEnforced: true,
    minAppVersion: manifest.minAppVersion,
  );
  final item = await showDialog<ExtensionItem>(
    context: context,
    builder: (_) => ExtensionEditDialog(item: preset, isNew: true),
  );
  if (item == null) {
    await store.deleteBundleDir(manifest.id); // 用户取消了：把刚解压出来的目录一并清掉
    return;
  }
  await store.add(item);
  toast('已导入「${item.name}」');
}

/// 导入 JSON：粘贴一份拓展 JSON（单条或数组），全部校验通过才入列。
Future<void> importExtensionJson({
  required BuildContext context,
  required ExtensionStore store,
  required void Function(String message) toast,
}) async {
  final list = await showExtensionImportDialog(context);
  if (list == null || !context.mounted) return;
  for (final item in list) {
    await store.add(item);
  }
  toast('已导入 ${list.length} 个拓展');
}

/// 下载 + 校验扫码得到的拓展包：下载过程弹不可取消的进度框，
/// 校验通过后把包里的名称 / id / 版本 / 权限列给用户，确认才解压入列。
Future<void> installScannedExtension({
  required BuildContext context,
  required ExtensionStore store,
  required void Function(String message) toast,
  required ScanBundleOutcome code,
}) async {
  final installer = ScannedBundleInstaller(store: store);
  final result = await showDialog<Object?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ExtensionDownloadDialog(
      label: '正在下载拓展…',
      task: () => installer.download(code),
    ),
  );
  if (!context.mounted) return;
  if (result is ExtensionDownloadFailure) {
    toast(describeScanError(result.error));
    return;
  }
  if (result is! ScannedBundle) return;
  final bundle = result;

  final ok = await confirmScannedInstall(context, bundle, code.url);
  if (!context.mounted || !ok) return;
  try {
    final item = await installer.install(bundle);
    toast('已安装「${item.name}」');
  } catch (e) {
    toast(describeScanError(e));
  }
}

/// 安装前确认：包里的清单（不是二维码里写的）才是最终内容，权限尤其要看清楚。
Future<bool> confirmScannedInstall(
  BuildContext context,
  ScannedBundle bundle,
  String url,
) async {
  final m = bundle.manifest;
  final perms = m.permissions.isEmpty
      ? '无'
      : describeSensitivePermissions(m.permissions).join('\n');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('安装「${m.name}」？'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.5,
        ),
        child: SingleChildScrollView(
          child: Text(
            'id：${m.id}\n'
            '版本：${m.version}\n'
            '来源：$url\n\n'
            '敏感权限：\n$perms',
            style: const TextStyle(fontSize: 12.5, height: 1.6),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('安装'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 把下载 / 解压错误翻成一句能给用户看的提示。
String describeScanError(Object e) {
  if (e is FormatException) return e.message;
  if (e is StateError) return e.message;
  if (e is TimeoutException) return '下载超时，请检查网络后重试';
  return '$e';
}
