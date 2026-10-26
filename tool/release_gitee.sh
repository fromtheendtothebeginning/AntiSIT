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
# 临时文件放在工作区的 build/ 下：Git Bash 的 /tmp 路径和 Windows 版 curl/python
# 不互通（body@/tmp/... 会读不到），用相对路径最稳；EXIT 时清掉。
TMP_DIR="build/gitee_release"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT
OUT_DIR="$TMP_DIR"
OUT_NAME="AntiSIT-$VERSION.apk"
OUT="$OUT_DIR/$OUT_NAME"

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
(cd "$OUT_DIR" && sha256sum "$OUT_NAME" > "$OUT_NAME.sha256")
REL_JSON="$TMP_DIR/release.json"
# Gitee 对「tag 还没有 Release」返回 200 + null（不是 404），不能只看 curl 退出码
curl -fsS "$API/repos/$REPO/releases/tags/$TAG?access_token=$TOKEN" -o "$REL_JSON" || true
rel_id() {
  python -c 'import json,sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = None
print(d.get("id", "") if isinstance(d, dict) else "")' "$REL_JSON"
}
REL_ID=$(rel_id)
if [ -z "$REL_ID" ]; then
  PREV=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)
  NOTES_FILE="$TMP_DIR/notes.txt"
  {
    echo "## AntiSIT $VERSION"
    echo
    echo "APK 直装（Android 7.0+）：下载 \`$OUT_NAME\` 安装，首次需允许「未知来源」。"
    echo
    echo "### 本次更新"
    if [ -n "$PREV" ]; then
      git log --no-merges --pretty='- %s' "$PREV..HEAD"
    else
      git log --no-merges --pretty='- %s' -n 10
    fi
  } > "$NOTES_FILE"
  # Gitee 建 Release 只认表单（JSON 会返回 null）；body 用文件交给 curl 编码，
  # 避免 Git Bash 的 GBK 终端把中文写成乱码。
  curl -fsS -X POST "$API/repos/$REPO/releases" \
    --data-urlencode "access_token=$TOKEN" \
    --data-urlencode "tag_name=$TAG" \
    --data-urlencode "target_commitish=main" \
    --data-urlencode "name=AntiSIT $VERSION" \
    --data-urlencode "body@$NOTES_FILE" \
    -o "$REL_JSON"
  REL_ID=$(rel_id)
fi
[ -n "$REL_ID" ] || { echo "创建 Gitee Release 失败：" >&2; head -c 500 "$REL_JSON" >&2; echo >&2; exit 1; }

# 5) 上传 APK 与校验文件（重跑时跳过同名附件，避免重复）
EXISTING=$(python -c 'import json,sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = None
print("\n".join(a.get("name", "") for a in (d.get("assets", []) if isinstance(d, dict) else [])))' "$REL_JSON")
for f in "$OUT" "$OUT.sha256"; do
  name=$(basename "$f")
  if printf '%s\n' "$EXISTING" | grep -Fxq "$name"; then
    echo "跳过已存在附件：$name"
    continue
  fi
  curl -fsS -X POST "$API/repos/$REPO/releases/$REL_ID/attach_files?access_token=$TOKEN" \
    -F "file=@$f" -o /dev/null
done

echo "Gitee Release: https://gitee.com/$REPO/releases/tag/$TAG"
