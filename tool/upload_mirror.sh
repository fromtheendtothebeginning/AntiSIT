#!/usr/bin/env bash
# 把本机构建的 AntiSIT APK 同步到 anticraft.top 镜像（分发直链 + App 更新检查兜底源）。
# 用法：bash tool/upload_mirror.sh <版本> [本机 APK 路径]
#
# 做完三件事：
#   1. 上传 AntiSIT-v<版本>.apk 与 .sha256，并核对服务器上的哈希与本机一致
#   2. 把 AntiSIT-latest.apk 软链指到新版本（站点下载按钮用它）
#   3. 用 GitHub Release API 的 JSON 生成 latest.json（下载地址改写成本站直链）并上传
#
# 站内文件名带 v 前缀（AntiSIT-v1.41.0.apk），而 sha256 文件里记的是不带 v 的名字，
# 所以校验必须直接比哈希值，不能 `sha256sum -c`（它会去找错文件名）。
set -euo pipefail

VERSION="${1:?用法: upload_mirror.sh <版本，如 1.41.0> [apk 路径]}"
APK="${2:-build/AntiSIT-$VERSION.apk}"
SHA="$APK.sha256"
HOST="root@47.100.125.150"
DIR="/var/www/anticraft/dist/apk"
SITE="https://anticraft.top/apk"
API="https://api.github.com/repos/fromtheendtothebeginning/AntiSIT/releases/latest"

[ -f "$APK" ] || { echo "找不到 $APK（先 flutter build apk --release 并拷成这个名字）" >&2; exit 1; }
[ -f "$SHA" ] || { echo "找不到 $SHA" >&2; exit 1; }

NAME="AntiSIT-v$VERSION.apk"
WANT=$(awk '{print $1}' "$SHA" | tr -d '\r')
BYTES=$(wc -c < "$APK" | tr -d ' ')

echo "上传 $APK ($BYTES B) -> $HOST:$DIR/$NAME"
scp -o BatchMode=yes "$APK" "$HOST:$DIR/$NAME.uploading"
scp -o BatchMode=yes "$SHA" "$HOST:$DIR/$NAME.sha256.uploading"
ssh -o BatchMode=yes "$HOST" \
  "cd '$DIR' && mv '$NAME.uploading' '$NAME' && mv '$NAME.sha256.uploading' '$NAME.sha256' && ln -sfn '$NAME' AntiSIT-latest.apk"

GOT=$(ssh -o BatchMode=yes "$HOST" "sha256sum '$DIR/$NAME' | awk '{print \$1}'" | tr -d '\r')
if [ "$GOT" != "$WANT" ]; then
  echo "哈希不一致：服务器 $GOT / 本机 $WANT" >&2
  exit 1
fi
echo "哈希一致：$GOT"

# latest.json：取 GitHub Release 的完整 JSON，把下载地址改写成本站直链。
# App 的 parseRelease 需要 tag_name、assets[].name 以 .apk / .apk.sha256 结尾、
# body 里有「### 本次更新」段（Release 工作流自动生成）。
JQ_TMP="build/latest-$VERSION.json"
curl -fsS -m 30 -H 'User-Agent: dsh' "$API" -o "$JQ_TMP"
python - "$JQ_TMP" "$VERSION" "$BYTES" <<'PY'
import json, sys

path, version, apk_bytes = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(path, encoding='utf-8') as f:
    data = json.load(f)

if data.get('tag_name') != f'v{version}':
    sys.exit(f"GitHub Release 是 {data.get('tag_name')}，与要发的 v{version} 不一致")

# 站内文件名带 v 前缀，GitHub 资产不带：逐项改名并指向本站。
hosted = []
for asset in data.get('assets', []):
    name = asset['name']
    if not (name.endswith('.apk') or name.endswith('.apk.sha256')):
        continue
    local = name.replace('AntiSIT-', 'AntiSIT-v', 1)
    asset['browser_download_url'] = f'https://anticraft.top/apk/{local}'
    asset['size'] = apk_bytes if local.endswith('.apk') else 86
    hosted.append(local)
if not any(n.endswith('.apk') and not n.endswith('.sha256') for n in hosted):
    sys.exit('GitHub Release 里没有 .apk 资产，无法生成 latest.json')

with open('build/latest.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print('latest.json assets:', hosted)
PY

scp -o BatchMode=yes build/latest.json "$HOST:$DIR/latest.json.uploading"
ssh -o BatchMode=yes "$HOST" "cd '$DIR' && mv latest.json.uploading latest.json"

echo "镜像就绪："
echo "  $SITE/$NAME"
echo "  $SITE/AntiSIT-latest.apk"
echo "  $SITE/latest.json"
