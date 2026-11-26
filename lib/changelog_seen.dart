import 'update_check.dart';

import 'changelog_entries.dart';

/// 上次打开时的版本号记在偏好里的键。
const String kChangelogSeenVersion = 'changelog_seen_version';

/// 比上次见过的版本（不含）新、且不晚于当前版本（含）的条目，新版本在前。
/// 首次安装（[since] 为 null）、版本没变、降级安装都返回空。
List<ChangelogEntry> changelogEntriesSince(String? since, String current) {
  if (since == null || since == current) return const [];
  return [
    for (final e in appChangelog)
      if (compareVersions(e.version, since) > 0 &&
          compareVersions(e.version, current) <= 0)
        e,
  ];
}