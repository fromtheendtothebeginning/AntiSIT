#!/usr/bin/env bash
# 把当前版本同步发布到 Gitee：建仓库（如不存在）→ 推 main/tag → 建 Release → 上传 APK。
# 用法：
#   GITEE_TOKEN=xxx tool/release_gitee.sh    # 完整发布（建仓库 + 推代码 + Release + APK）
#   tool/release_gitee.sh                    # 只推代码和 tag（仓库需已存在；Release 到网页建）
#   GITEE_TOKEN  Gitee 私人令牌（https://gitee.com/profile/personal_access_tokens，勾选 projects）
#                也可写到 ~/.gitee_token（一行，仅令牌），不必贴进命令行
#   GITEE_REPO   可选，默认 ender123/AntiSIT
# 前置：本机 SSH key 已加到 Gitee（git@gitee.com 可免密），当前版本 APK 已构建。
set -euo pipefail

REPO="${GITEE_REPO:-ender123/AntiSIT}"
TOKEN="${GITEE_TOKEN:-}"
# 不想把令牌贴进聊天/命令行时，写到 ~/.gitee_token（一行，仅令牌）
[ -n "$TOKEN" ] || TOKEN=$(cat "$HOME/.gitee_token" 2>/dev/null || true)
API="https://gitee.com/api/v5"
VERSION=$(sed -n 's/^version: *\([0-9][0-9.]*\)+.*/\1/p' pubspec.yaml)
TAG="v$VERSION"
APK="build/app/outputs/flutter-apk/app-release.apk"
OUT="AntiSIT-$VERSION.apk"

[ -n "$VERSION" ] || { echo "读不到 pubspec.yaml 的 version" >&2; exit 1; }

# 1) 有令牌时：仓库不存在就创建（公开仓库，Release 附件才能匿名下载）
if [ -n "$TOKEN" ] && ! curl -fsS "$API/repos/$REPO?access_token=$TOKEN" -o /dev/null; then
  echo "创建 Gitee 仓库 $REPO ..."
  curl -fsS -X POST "$API/user/repos?access_token=$TOKEN" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"${REPO#*/}\",\"path\":\"${REPO#*/}\",\"private\":false,\"auto_init\":false}" \
    -o /dev/null
fi

# 2) 推送代码与 tag（走 SSH，不把令牌写进 git 配置）
git remote get-url gitee >/dev/null 2>&1 || git remote add gitee "git@gitee.com:$REPO.git"
git push gitee main
git push gitee "$TAG"

# 3) 没有令牌：只推代码，Release 交给网页
if [ -z "$TOKEN" ]; then
  echo "代码与 tag 已推送。创建 Release（上传 $APK）："
  echo "  https://gitee.com/$REPO/releases/new?tag=$TAG"
  exit 0
fi

# 4) 建 Release（已存在就复用）
[ -f "$APK" ] || { echo "找不到 $APK，先 flutter build apk --release" >&2; exit 1; }
cp "$APK" "$OUT"
sha256sum "$OUT" > "$OUT.sha256"
REL_JSON=$(mktemp)
if ! curl -fsS "$API/repos/$REPO/releases/tags/$TAG?access_token=$TOKEN" -o "$REL_JSON"; then
  PREV=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)
  if [ -n "$PREV" ]; then
    NOTES=$(git log --no-merges --pretty='- %s' "$PREV..HEAD")
  else
    NOTES=$(git log --no-merges --pretty='- %s' -n 10)
  fi
  BODY=$(VERSION="$VERSION" NOTES="$NOTES" python -c '
import json, os
v = os.environ["VERSION"]
print(json.dumps({"tag_name": "v" + v, "target_commitish": "main",
                  "name": "AntiSIT " + v,
                  "body": "## AntiSIT " + v + "\n\n安装包见附件。\n\n### 本次更新\n" + os.environ["NOTES"] + "\n"}))
')
  curl -fsS -X POST "$API/repos/$REPO/releases?access_token=$TOKEN" \
    -H 'Content-Type: application/json' -d "$BODY" -o "$REL_JSON"
fi
REL_ID=$(python -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$REL_JSON")

# 5) 上传 APK 与校验文件
for f in "$OUT" "$OUT.sha256"; do
  curl -fsS -X POST "$API/repos/$REPO/releases/$REL_ID/attach_files?access_token=$TOKEN" \
    -F "file=@$f" -o /dev/null
done

echo "Gitee Release: https://gitee.com/$REPO/releases/tag/$TAG"
