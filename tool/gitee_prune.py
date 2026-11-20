#!/usr/bin/env python3
"""清理 Gitee Release 里过老的 APK 附件，给新版本腾配额。

Gitee 仓库的 **Release 附件总量上限 1 GB**，每个 APK 约 87 MB，也就是十来个版本
就满了——传新 APK 时会返回 `验证失败：文件大小已超出仓库附件配额：1 GB`。
更新链路只分发最新版，老 APK 没人下载（源码都在 git tag 里），所以按版本号
保留最近 N 个，其余删掉。

用法::

    GITEE_TOKEN=xxx python tool/gitee_prune.py                    # 保留最近 5 个版本
    GITEE_TOKEN=xxx python tool/gitee_prune.py --keep 3
    GITEE_TOKEN=xxx python tool/gitee_prune.py --dry-run          # 只报告不删
    GITEE_TOKEN=xxx python tool/gitee_prune.py --repo ender123/AntiSIT

只删 `.apk` 与 `.apk.sha256` 两类附件；Release 本身和别的附件一律不动。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "https://gitee.com/api/v5"

# 只清理这两类附件：Release 里还可能有源码包（v1.2.3.zip / .tar.gz）之类的，
# 它们由 Gitee 自动生成、体积也小，不该被误删。
PRUNABLE_SUFFIXES = (".apk", ".apk.sha256")

_VERSION_RE = re.compile(r"^v?(\d+(?:\.\d+)*)")


def parse_version(tag: str) -> tuple[int, ...] | None:
    """'v1.41.7' -> (1, 41, 7)；认不出来返回 None（这种版本一律不动）。"""
    match = _VERSION_RE.match((tag or "").strip())
    if not match:
        return None
    return tuple(int(part) for part in match.group(1).split("."))


def request(url: str, method: str = "GET") -> object:
    req = urllib.request.Request(url, method=method, headers={"User-Agent": "AntiSIT-release"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = resp.read().decode("utf-8", "replace").strip()
    if not body:
        return None
    return json.loads(body)


def list_releases(repo: str, token: str) -> list[dict]:
    """翻页取全部 Release。Gitee 每页最多 100，翻到空页为止。"""
    out: list[dict] = []
    page = 1
    while page <= 20:  # 20 页 = 2000 个 Release，够用且能防死循环
        query = urllib.parse.urlencode(
            {"access_token": token, "page": page, "per_page": 100}
        )
        data = request(f"{API}/repos/{repo}/releases?{query}")
        if not isinstance(data, list) or not data:
            break
        out.extend(item for item in data if isinstance(item, dict))
        if len(data) < 100:
            break
        page += 1
    return out


def list_assets(repo: str, release_id: int, token: str) -> list[dict]:
    query = urllib.parse.urlencode({"access_token": token})
    try:
        data = request(f"{API}/repos/{repo}/releases/{release_id}/attach_files?{query}")
    except urllib.error.HTTPError as exc:
        print(f"  跳过 release {release_id}：列附件失败（HTTP {exc.code}）", file=sys.stderr)
        return []
    if not isinstance(data, list):
        return []
    return [item for item in data if isinstance(item, dict)]


def human(size: int) -> str:
    return f"{size / 1024 / 1024:.1f} MB"


def main() -> int:
    parser = argparse.ArgumentParser(description="按版本号保留最近几个 Gitee Release 的 APK 附件")
    parser.add_argument(
        "--repo",
        default=os.environ.get("GITEE_REPO", "ender123/AntiSIT"),
        help="owner/name，默认 ender123/AntiSIT",
    )
    parser.add_argument("--keep", type=int, default=5, help="保留最近的几个版本，默认 5")
    parser.add_argument("--dry-run", action="store_true", help="只报告，不真的删")
    args = parser.parse_args()

    token = os.environ.get("GITEE_TOKEN", "").strip()
    if not token:
        token_file = os.path.join(os.path.expanduser("~"), ".gitee_token")
        if os.path.isfile(token_file):
            with open(token_file, encoding="utf-8") as handle:
                token = handle.read().strip()
    if not token:
        print("缺 GITEE_TOKEN（或 ~/.gitee_token）", file=sys.stderr)
        return 1

    releases = list_releases(args.repo, token)
    if not releases:
        print("没有读到任何 Release")
        return 0

    # 按版本号从新到旧；认不出 tag 的（手滑建的）排在最后且永不删
    versioned: list[tuple[tuple[int, ...], dict]] = []
    unversioned: list[dict] = []
    for rel in releases:
        version = parse_version(str(rel.get("tag_name", "")))
        if version is None:
            unversioned.append(rel)
        else:
            versioned.append((version, rel))
    versioned.sort(key=lambda item: item[0], reverse=True)

    keep_versions = {version for version, _ in versioned[: max(args.keep, 1)]}
    print(f"{args.repo}：{len(releases)} 个 Release，保留最近 {max(args.keep, 1)} 个版本")
    for version, rel in versioned[: max(args.keep, 1)]:
        print(f"  保留 v{'.'.join(map(str, version))}")

    doomed: list[tuple[str, int, dict]] = []
    kept_bytes = 0
    total_bytes = 0
    for version, rel in versioned:
        assets = [
            asset
            for asset in list_assets(args.repo, int(rel["id"]), token)
            if str(asset.get("name", "")).endswith(PRUNABLE_SUFFIXES)
        ]
        size = sum(int(asset.get("size") or 0) for asset in assets)
        total_bytes += size
        if version in keep_versions:
            kept_bytes += size
            continue
        for asset in assets:
            doomed.append((str(rel.get("tag_name", "")), int(rel["id"]), asset))

    print(f"当前附件合计 {human(total_bytes)}，其中保留部分 {human(kept_bytes)}")

    if not doomed:
        print("没有需要清理的老版本附件")
        return 0

    freed = sum(int(asset.get("size") or 0) for _, _, asset in doomed)
    print(f"待清理 {len(doomed)} 个附件，可释放 {human(freed)}")
    if args.dry_run:
        for tag, _, asset in doomed:
            print(f"  [dry-run] {tag} {asset.get('name')}")
        return 0

    failed = 0
    for tag, release_id, asset in doomed:
        query = urllib.parse.urlencode({"access_token": token})
        url = f"{API}/repos/{args.repo}/releases/{release_id}/attach_files/{asset.get('id')}?{query}"
        try:
            request(url, method="DELETE")
            print(f"  已删 {tag} {asset.get('name')}")
        except urllib.error.HTTPError as exc:
            failed += 1
            print(f"  删除失败 {tag} {asset.get('name')}（HTTP {exc.code}）", file=sys.stderr)
        except Exception as exc:  # noqa: BLE001 - 网络抖动不该让发版脚本崩掉
            failed += 1
            print(f"  删除失败 {tag} {asset.get('name')}（{exc}）", file=sys.stderr)

    if failed:
        print(f"{failed} 个附件没删掉", file=sys.stderr)
        return 1
    print(f"已清理 {len(doomed)} 个附件，释放约 {human(freed)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
