import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'changelog_seen.dart';

/// 升级后第一次打开 → 弹更新日志。首次安装不弹（没有「更新」发生，只记下当前版本），
/// 版本没变也不弹。返回是否展示了弹窗。
Future<bool> showChangelogIfUpdated(
  BuildContext context,
  String current,
) async {
  final sp = await SharedPreferences.getInstance();
  final seen = sp.getString(kChangelogSeenVersion);
  if (seen == null) {
    await sp.setString(kChangelogSeenVersion, current);
    return false;
  }
  final entries = changelogEntriesSince(seen, current);
  // 先记再弹：看完关掉就算完，不区分「已读」；降级安装也记下，避免每次启动都弹
  await sp.setString(kChangelogSeenVersion, current);
  if (entries.isEmpty || !context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('更新日志'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                Text(
                  '${entries[i].version} · ${entries[i].date}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                for (final n in entries[i].notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('· $n', style: const TextStyle(fontSize: 13)),
                  ),
                if (i < entries.length - 1) const Divider(height: 20),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
  return true;
}