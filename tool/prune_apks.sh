#!/usr/bin/env bash
# 清掉 build/ 下堆积的旧安装包：每发一版都会留一个 80MB+ 的 APK，
# 时间一长 build/app、build/dist、build/mirror 里能攒几十个（实测一次清出 4.5GB）。
#
# 用法：tool/prune_apks.sh [保留个数]      # 默认保留最新 3 个
#
# 规则：
#   * 只认 build/ 下的 *.apk 与它们的 .sha256 / .sha1 伴生文件，别的一概不碰；
#   * 按修改时间从新到旧排序，保留最新 N 个（连同伴生文件），其余删除；
#   * 正在发版用的 build/app/outputs/flutter-apk/app-release.apk 永远保留。
set -euo pipefail

KEEP="${1:-3}"
ROOT="build"
ALWAYS_KEEP="build/app/outputs/flutter-apk/app-release.apk"

[ -d "$ROOT" ] || { echo "没有 $ROOT 目录，跳过"; exit 0; }

deleted=0
freed=0
kept=0
while IFS=$'\t' read -r _ apk; do
  [ -n "$apk" ] || continue
  if [ "$apk" = "$ALWAYS_KEEP" ]; then
    continue   # 当前发版用的那份：永远留着，也不占「保留 N 个」的名额
  fi
  if [ "$kept" -lt "$KEEP" ]; then
    kept=$((kept + 1))
    continue
  fi
  bytes=$(wc -c < "$apk" | tr -d " ")
  rm -f "$apk" "$apk.sha256" "$apk.sha1"
  freed=$((freed + bytes))
  deleted=$((deleted + 1))
done < <(find "$ROOT" -type f -name '*.apk' -printf '%T@\t%p\n' 2>/dev/null | sort -rn -k1,1)

if [ "$deleted" -eq 0 ]; then
  echo "安装包数量未超过 $KEEP，无需清理"
else
  echo "已删除 $deleted 个旧安装包，释放 $((freed / 1024 / 1024)) MB（保留最新 $kept 个）"
fi
