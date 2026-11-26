import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import '../extension_item.dart';
import '../ext_icon.dart';
import '../ext_permissions.dart';
import 'market_entry.dart';

/// 市场里一条拓展的卡片：图标、名称 / 版本 / 角标、简介、操作按钮。
class MarketEntryCard extends StatelessWidget {
  const MarketEntryCard({
    super.key,
    required this.entry,
    required this.installed,
    required this.update,
    required this.needsApp,
    required this.focused,
    required this.busy,
    required this.onOpen,
    required this.onInstall,
    required this.onUninstall,
  });

  final MarketEntry entry;

  /// 已装的那条（没装为 null）。
  final ExtensionItem? installed;
  final bool update;
  final bool needsApp;
  final bool focused;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final canOpen = installed != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        onTap: canOpen ? onOpen : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExtIcon(item: _entryAsItem(e)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(e.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                          if (e.version.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text('v${e.version}',
                                style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
                          ],
                          if (update) ...[
                            const SizedBox(width: 6),
                            Capsule('有新版', color: SemColors.accent),
                          ],
                          if (focused) ...[
                            const SizedBox(width: 6),
                            Capsule('已定位', color: SemColors.warning),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(e.desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, height: 1.45, color: SemColors.textSecondary)),
                      const SizedBox(height: 5),
                      Text(
                        [
                          if (e.author.isNotEmpty) e.author,
                          e.category,
                          if (!e.isBundle) '网址',
                          if (!e.official) '第三方',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: SemColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (needsApp)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('需要升级 App（≥${e.minAppVersion}）',
                        style: TextStyle(fontSize: 11.5, color: SemColors.danger)),
                  ),
                if (installed != null && !update)
                  IconButton(
                    tooltip: '卸载',
                    visualDensity: VisualDensity.compact,
                    onPressed: onUninstall,
                    icon: Icon(Icons.delete_outline, size: 18, color: SemColors.textMuted),
                  ),
                if (installed != null && !update)
                  const SizedBox(width: 6),
                if (installed != null && !update)
                  OutlinedButton(onPressed: onOpen, child: const Text('打开'))
                else if (needsApp)
                  const FilledButton(onPressed: null, child: Text('装不了'))
                else
                  FilledButton(
                    onPressed: busy ? null : onInstall,
                    child: Text(update ? '更新' : '安装'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 市场目录拉不到时的错误卡（带重试）。
class MarketErrorBox extends StatelessWidget {
  const MarketErrorBox({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('市场目录用不了',
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.bold, color: SemColors.danger)),
              const SizedBox(height: 6),
              Text(message,
                  style: TextStyle(fontSize: 12, color: SemColors.textSecondary, height: 1.6)),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                    onPressed: onRetry, child: const Text('重试')),
              ),
            ],
          ),
        ),
      );
}

/// 单个第三方源出错时的提示卡（带重试）。
class MarketSourceErrorBox extends StatelessWidget {
  const MarketSourceErrorBox({
    super.key,
    required this.label,
    required this.message,
    required this.onRetry,
  });

  final String label;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: AppCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 16, color: SemColors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('源「$label」用不了',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: SemColors.danger)),
                    const SizedBox(height: 4),
                    Text(message,
                        style: TextStyle(
                            fontSize: 11.5, color: SemColors.textSecondary, height: 1.6)),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: onRetry,
                        child: const Text('重试', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// 「N 个拓展有新版 + 全部更新」横幅：只在有可更新条目时出现。
class MarketUpdateBanner extends StatelessWidget {
  const MarketUpdateBanner({
    super.key,
    required this.count,
    required this.busy,
    required this.onUpdateAll,
  });

  final int count;
  final bool busy;
  final VoidCallback onUpdateAll;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: SemColors.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SemColors.accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.system_update_alt_rounded, size: 18, color: SemColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$count 个拓展有新版',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            FilledButton.tonal(
              onPressed: busy ? null : onUpdateAll,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('全部更新', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
}

/// 一行灰字提示（例如在用缓存目录）。
class MarketNoteBox extends StatelessWidget {
  const MarketNoteBox({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(text,
            style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6)),
      );
}

/// 过滤后没有条目时的空态。
class MarketEmpty extends StatelessWidget {
  const MarketEmpty({super.key, required this.catalogEmpty});

  /// 整个目录都空（而不是当前过滤没命中）。
  final bool catalogEmpty;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 24),
        child: Center(
          child: Text(
            catalogEmpty
                ? '市场里还没有拓展。想放一个上来？看市场仓库的投稿说明。'
                : '没找到符合条件的拓展。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: SemColors.textMuted, height: 1.7),
          ),
        ),
      );
}

/// 装 / 更新之前的确认框：把来源、版本、大小和敏感权限摊开。
Future<bool?> showMarketInstallDialog(
  BuildContext context,
  MarketEntry e, {
  required bool update,
  required String? installedVersion,
  required String thirdPartyLabel,
}) {
  final perms = describeSensitivePermissions(e.permissions);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(update ? '更新「${e.name}」？' : '安装「${e.name}」？'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv(
                '来源',
                e.official
                    ? '插件市场 · ${e.author.isEmpty ? '佚名' : e.author}'
                    : '第三方源 · $thirdPartyLabel'),
            if (e.version.isNotEmpty)
              _kv('版本', update ? '$installedVersion → ${e.version}' : e.version),
            if (e.isBundle && e.size > 0) _kv('大小', formatMarketBytes(e.size)),
            _kv('分类', e.category),
            if (e.desc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(e.desc, style: const TextStyle(fontSize: 12.5, height: 1.6)),
            ],
            const SizedBox(height: 12),
            Text('它要用的接口', style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
            const SizedBox(height: 6),
            if (perms.isEmpty)
              Text('只是读配色、弹提示、改自己的卡片这类界面接口。',
                  style: TextStyle(fontSize: 12, color: SemColors.textSecondary, height: 1.6))
            else
              for (final p in perms)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('· $p',
                      style: TextStyle(fontSize: 12, color: SemColors.textSecondary, height: 1.5)),
                ),
            const SizedBox(height: 10),
            if (!e.official) ...[
              Text('第三方源：内容由作者自己发布，没有经过官方审核（收录 ≠ 背书）。',
                  style: TextStyle(fontSize: 11.5, color: SemColors.danger, height: 1.6)),
              const SizedBox(height: 6),
            ],
            Text(
              e.isBundle
                  ? (update
                      ? '更新只换页面内容，拓展里存的数据（设置、历史）留着。'
                      : '内容来自插件市场，已过签名与哈希校验；装好后随时能卸载。')
                  : '网址型：打开的是第三方网站，内容由站点控制、随时可能变化，'
                      'App 只保证「这个地址是市场登记的」。',
              style: TextStyle(fontSize: 11.5, color: SemColors.textMuted, height: 1.6),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(update ? '更新' : '安装')),
      ],
    ),
  );
}

/// 市场条目画成卡片图标要的样子（本地包没有 favicon 可抓，所以 bundled 留空）。
ExtensionItem _entryAsItem(MarketEntry e) => ExtensionItem(
      id: e.id,
      name: e.name,
      url: e.url,
      icon: e.icon,
      // bundle 条目的 url 是空的（真正的地址在 base + zip），标成 bundled
      // 图标就走 emoji / 首字，不会去抓站点图标
      bundled: e.isBundle,
    );

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(k, style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
          ),
          Expanded(
            child: Text(v,
                style: const TextStyle(fontSize: 12.5, height: 1.5)),
          ),
        ],
      ),
    );

/// 文件大小，例如 `1.2 MB`。
String formatMarketBytes(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
        ? '${(bytes / 1024).toStringAsFixed(1)} KB'
        : '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';

/// 相对时间，例如 `3 分钟前`。
String formatMarketWhen(DateTime? t) {
  if (t == null) return '时间未知';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return '刚刚';
  if (d.inHours < 1) return '${d.inMinutes} 分钟前';
  if (d.inDays < 1) return '${d.inHours} 小时前';
  return '${d.inDays} 天前';
}

/// 把异常压成一行短提示（最多 120 字）。
String shortMarketError(Object e) {
  final s = '$e'.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
  return s.length > 120 ? '${s.substring(0, 120)}…' : s;
}
