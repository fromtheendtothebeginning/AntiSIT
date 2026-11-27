#!/usr/bin/env bash
# 生成 Release 说明的「### 本次更新」段：**优先用 App 内更新日志里这一版的条目**
# （lib/changelog_entries.dart），取不到再退回 git log。
#
# 为什么：git log 里全是「发版：…」「测试：清掉冗余 import」这类工程提交，用户
# 在更新的弹窗里看到的是这些，等于没有说明。而 changelog_entries.dart 是写给用户
# 看的（每条一句人话），两个渠道复用同一份文案就不会两处不一致。
#
# 用法：bash tool/release_notes.sh <version>   # version 不带 +构建号，如 1.48.1-dev.1
set -euo pipefail

VERSION="${1:?用法: release_notes.sh <版本>}"
ENTRIES="lib/changelog_entries.dart"

extract_from_changelog() {
  [ -f "$ENTRIES" ] || return 1
  python - "$ENTRIES" "$VERSION" <<'PY'
import io, re, sys

path, version = sys.argv[1], sys.argv[2]
text = io.open(path, encoding='utf-8').read()
# 条目形如：ChangelogEntry(version: '1.48.1-dev.1', date: '...', notes: ['…', '…'])
blocks = re.findall(
    r"ChangelogEntry\(\s*version:\s*'([^']+)'.*?notes:\s*\[(.*?)\]\s*,?\s*\)",
    text, re.S)
for v, body in blocks:
    if v.strip() != version:
        continue
    for line in re.findall(r"'((?:[^'\\]|\\.)*)'", body):
        line = line.replace("\\'", "'").strip()
        if line:
            print('- ' + line)
    sys.exit(0)
sys.exit(1)
PY
}

if extract_from_changelog; then
  exit 0
fi

# 退回 git log：取最近一个 tag 之后的提交（没有 tag 就给最近 10 条）
PREV=$(git describe --tags --abbrev=0 'HEAD^' 2>/dev/null || true)
if [ -n "$PREV" ]; then
  git log --no-merges --pretty='- %s' "$PREV..HEAD"
else
  git log --no-merges --pretty='- %s' -n 10
fi
