#!/usr/bin/env bash
# 把当前版本同步发布到 Gitee：建仓库（如不存在）→ 推 main/tag → 建 Release → 上传 APK。
# 用法：
#   GITEE_TOKEN=xxx tool/release_gitee.sh    # 完整发布（建仓库 + 推代码 + Release + APK）
#   tool/release_gitee.sh                    # 只推代码和 tag（仓库需已存在；Release 到网页建）
#   GITEE_TOKEN  Gitee 私人令牌（https://gitee.com/profile/personal_access_tokens，勾选 projects）
#                也可写到 ~/.gitee_token（一行，仅令牌），不必贴进命令行
#   GITEE_REPO   可选，默认 ender123/AntiSIT
#   GITEE_KEEP_VERSIONS  可选，保留最近几个版本的 APK 附件，默认 5
# 前置：本机 SSH key 已加到 Gitee（git@gitee.com 可免密），当前版本 APK 已构建。
#
# 附件配额：Gitee 仓库的 Release 附件合计上限 1 GB，每个 APK 约 87 MB，十来个版本就满。
# 所以上传前会自动跑一遍 tool/gitee_prune.py（按版本号保留最近 GITEE_KEEP_VERSIONS 个）。
set -euo pipefail

REPO="${GITEE_REPO:-ender123/AntiSIT}"
TOKEN="${GITEE_TOKEN:-}"
# 不想把令牌贴进聊天/命令行时，写到 ~/.gitee_token（一行，仅令牌）
[ -n "$TOKEN" ] || TOKEN=$(cat "$HOME/.gitee_token" 2>/dev/null || true)
API="https://gitee.com/api/v5"
# 版本号可能带预发布段（1.48.0-dev.2+206）：内测版 tag 用 dev-<version>，
# 稳定版 tag 用 v<version>，与 GitHub 的 release.yml 保持同一套约定。
VERSION=$(sed -n 's/^version: *\([0-9][0-9A-Za-z.+-]*\)$/\1/p' pubspec.yaml | head -1)
VERSION=${VERSION%%+*}
case "$VERSION" in
  *-*) CHANNEL=dev; TAG="dev-$VERSION" ;;
  *)   CHANNEL=stable; TAG="v$VERSION" ;;
esac
APK="build/app/outputs/flutter-apk/app-release.apk"
# 临时文件放在工作区的 build/ 下：Git Bash 的 /tmp 路径和 Windows 版 curl/python
# 不互通（body@/tmp/... 会读不到），用相对路径最稳；EXIT 时清掉。
TMP_DIR="build/gitee_release"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
# 清老附件会刷一屏日志：与发版信息混在一起很难看出到底成没成功，所以分两份日志。
PRUNE_LOG="$TMP_DIR/prune.log"
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
# 防呆：APK 的 versionCode 必须与 pubspec 的构建号一致——后台构建没跑完就跑本脚本，
# 会把上一个版本的旧包当成新版本发出去（2026-11-08 v1.27.0 实际发生过）。
find_aapt() {
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$LOCALAPPDATA/Android/Sdk}}"
  ls "$sdk"/build-tools/*/aapt.exe 2>/dev/null | sort | tail -1
}
AAPT_BIN=$(find_aapt)
if [ -n "$AAPT_BIN" ]; then
  APK_CODE=$("$AAPT_BIN" dump badging "$APK" | sed -n "s/^package:.*versionCode='\([0-9]*\)'.*/\1/p")
  WANT_CODE=$(sed -n 's/^version: *[0-9.]*+\([0-9]*\)/\1/p' pubspec.yaml)
  if [ "$APK_CODE" != "$WANT_CODE" ]; then
    echo "APK versionCode=$APK_CODE 与 pubspec 构建号 $WANT_CODE 不一致：构建未完成或已过期，拒绝发版" >&2
    exit 1
  fi
else
  echo "警告：找不到 aapt，跳过 APK 版本核对（请确认 APK 是用当前版本新构建的）" >&2
fi
cp "$APK" "$OUT"
(cd "$OUT_DIR" && sha256sum "$OUT_NAME" > "$OUT_NAME.sha256")
REL_JSON="$TMP_DIR/release.json"
# Gitee 对「tag 还没有 Release」返回 200 + null（不是 404），不能只看 curl 退出码
curl -fsS "$API/repos/$REPO/releases/tags/$TAG?access_token=$TOKEN" -o "$REL_JSON" || true
# 解析 Release JSON 的两个 python 小片段都**必须显式 encoding='utf-8'**：
# 中文 Windows 的默认编码是 cp936，而 Gitee 返回的 JSON 里含中文（name/body），
# 不指定就是 UnicodeDecodeError → 解析成空 → 误判「Release 不存在」→ 重复创建
# 拿到 400，整个发版卡死在这一步。
rel_id() {
  python -c 'import json,sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
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
    if [ "$CHANNEL" = "dev" ]; then
      echo "**内测版**：会收到正在开发中的改动，可能不稳定；App 的「内测版」渠道只跟带预发布段的版本。"
      echo
    fi
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
    --data-urlencode "prerelease=$([ "$CHANNEL" = dev ] && echo true || echo false)" \
    --data-urlencode "body@$NOTES_FILE" \
    -o "$REL_JSON"
  REL_ID=$(rel_id)
fi
[ -n "$REL_ID" ] || { echo "创建 Gitee Release 失败：" >&2; head -c 500 "$REL_JSON" >&2; echo >&2; exit 1; }

# 5) 上传 APK 与校验文件（重跑时跳过同名附件，避免重复）
#
# 先清老版本：Gitee 仓库的** Release 附件总量上限 1 GB**，每个 APK 约 87 MB，
# 十来个版本就满——满了之后 attach_files 会回 400「文件大小已超出仓库附件配额」，
# 发版就卡在这一步。更新链路只分发最新版，老 APK 没人下载（源码都在 git tag 里），
# 所以按版本号保留最近 KEEP_VERSIONS 个。清理失败不挡发版：配额还够时照样能传。
KEEP_VERSIONS="${GITEE_KEEP_VERSIONS:-5}"
if [ -f tool/gitee_prune.py ]; then
  echo "清理过老的 Release 附件（保留最近 $KEEP_VERSIONS 个版本，日志见 $PRUNE_LOG）..."
  # PYTHONIOENCODING：中文 Windows 上 Python 默认按 cp936 输出，而下面要 grep 的是
  # UTF-8 中文关键词——不指定编码时 grep 一个字都匹配不上（表现成「清理静默无输出」）。
  if PYTHONIOENCODING=utf-8 GITEE_TOKEN="$TOKEN" python tool/gitee_prune.py \
    --repo "$REPO" --keep "$KEEP_VERSIONS" > "$PRUNE_LOG" 2>&1; then
    # 只把「释放了多少」这类结论说一句，明细留在日志里
    grep -E '待清理|已清理|没有需要清理' "$PRUNE_LOG" | tail -2 | sed 's/^/  /' || true
  else
    echo "  警告：清理老附件失败，继续尝试上传（明细见 $PRUNE_LOG）" >&2
  fi
fi

EXISTING=$(python -c 'import json,sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
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

# 6) 清本机 build/ 下堆积的旧安装包：每版都留 80MB+，不清能攒到几个 G。
#    只留最新几个（含刚发的这版），失败不影响发版结果。
if [ -f tool/prune_apks.sh ]; then
  bash tool/prune_apks.sh "${APK_KEEP_VERSIONS:-3}" || true
fi
