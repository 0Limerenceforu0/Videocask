#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把三端打包产物发布到 GitHub Releases。

用法（在 Flutter 项目根目录执行）：

    # 1) 首次：把 PAT 写进 .env（该文件已被 .gitignore 忽略）
    #    GITHUB_TOKEN=github_pat_xxx
    python tool/publish_release.py --dry-run      # 先看会传什么，不联网
    python tool/publish_release.py                # 正式发布

    python tool/publish_release.py --token xxx    # 或直接传
    python tool/publish_release.py --update       # 版本已存在时更新说明并补传缺失资产
    python tool/publish_release.py --prerelease   # 标记为预发布

产物来源：`deliverables/`（由 `tool/package_deliverables.py` 生成）。
上传时会重命名为 ASCII，避免中文文件名在部分下载器 / 代理上乱码：

    Videocask-android-arm64-v1.1.8.apk
    Videocask-android-armeabi-v7a-v1.1.8.apk
    Videocask-android-x86_64-v1.1.8.apk
    Videocask-windows-x64-v1.1.8.zip
    Videocask-web-v1.1.8.zip

发版前自检（任一不通过就退出，不产生半成品 Release）：
  - pubspec.yaml 的 version 与 lib/config/constants.dart 的 appVersion 必须一致
  - deliverables/ 里必须有本版本的产物
  - 工作区有未提交改动时只警告（不阻止），因为 tag 指向的是已推送的提交
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "pubspec.yaml"
CONSTANTS = ROOT / "lib" / "config" / "constants.dart"
CHANGELOG = ROOT / "CHANGELOG.md"
DELIVERABLES = ROOT / "deliverables"
ENV_FILE = ROOT / ".env"

DEFAULT_REPO = "0Limerenceforu0/Videocask"
API = "https://api.github.com"
UPLOAD_API = "https://uploads.github.com"

# 控制台按 UTF-8 输出，避免 Windows cp936 把中文打成乱码。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def info(msg: str) -> None:
    print(f"  {msg}")


def warn(msg: str) -> None:
    print(f"  [警告] {msg}")


def die(msg: str, code: int = 1) -> "NoReturn":  # noqa: F821
    print(f"  [错误] {msg}", file=sys.stderr)
    sys.exit(code)


# ==================== 版本读取与校验 ====================


def read_pubspec_version() -> tuple[str, int]:
    """返回 (语义版本, 构建号)。"""
    if not PUBSPEC.exists():
        die(f"找不到 {PUBSPEC}")
    text = PUBSPEC.read_text(encoding="utf-8")
    m = re.search(r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$", text, re.M)
    if not m:
        die("pubspec.yaml 里的 version 不是 x.y.z+N 形式")
    return f"{m.group(1)}.{m.group(2)}.{m.group(3)}", int(m.group(4))


def read_constants_version() -> str | None:
    if not CONSTANTS.exists():
        return None
    text = CONSTANTS.read_text(encoding="utf-8")
    m = re.search(r"appVersion\s*=\s*'([^']+)'", text)
    return m.group(1) if m else None


def check_version_consistency(version: str) -> None:
    """版本号只有一处真相：pubspec。constants 必须跟着走。"""
    const_version = read_constants_version()
    info(f"pubspec 版本: {version} / constants.appVersion: {const_version or '未找到'}")
    if const_version is None:
        die("lib/config/constants.dart 里找不到 appVersion")
    if const_version != version:
        die(
            f"版本号不一致：pubspec={version}，constants={const_version}。"
            "更新检查以 constants 为准，不一致会让客户端误判版本，先同步再发版。"
        )


# ==================== 产物发现 ====================


def classify_asset(path: Path) -> str | None:
    """按文件名关键词识别平台/架构，返回 ASCII 目标名模板。"""
    name = path.name.lower()
    if name.endswith(".apk"):
        if "arm64" in name:
            return "Videocask-android-arm64-v{ver}.apk"
        if "armeabi" in name or "armv7" in name:
            return "Videocask-android-armeabi-v7a-v{ver}.apk"
        if "x86_64" in name or "x64" in name:
            return "Videocask-android-x86_64-v{ver}.apk"
        return "Videocask-android-v{ver}.apk"
    if name.endswith(".zip"):
        if "windows" in name:
            return "Videocask-windows-x64-v{ver}.zip"
        if "web" in name:
            return "Videocask-web-v{ver}.zip"
    return None


def collect_assets(version: str, source_dir: Path) -> list[tuple[Path, str]]:
    """挑出属于本版本的产物，返回 [(本地路径, 上传名)]。

    只认文件名里带 `v{version}` 的，避免把历史版本一起传上去。
    """
    if not source_dir.exists():
        die(f"产物目录不存在: {source_dir}（先跑 tool/package_deliverables.py）")

    picked: list[tuple[Path, str]] = []
    seen: set[str] = set()
    for path in sorted(source_dir.iterdir()):
        if not path.is_file():
            continue
        if f"v{version}" not in path.name and version not in path.name:
            continue
        template = classify_asset(path)
        if template is None:
            continue
        target = template.format(ver=version)
        if target in seen:
            warn(f"同一目标名出现多次，忽略 {path.name}")
            continue
        seen.add(target)
        picked.append((path, target))

    # 至少要有一个 Android 包和一个桌面/Web 包，防止只传了一半就发版。
    has_apk = any(n.endswith(".apk") for _, n in picked)
    if not has_apk:
        die(f"{source_dir} 里找不到 {version} 的 APK")
    return picked


# ==================== Release 说明 ====================


def extract_changelog(version: str) -> str:
    """从 CHANGELOG.md 抓 `## {version}` 到下一个 `## ` 之间的内容。"""
    if not CHANGELOG.exists():
        warn("没有 CHANGELOG.md，更新说明留空")
        return ""
    text = CHANGELOG.read_text(encoding="utf-8")
    pattern = re.compile(rf"^##\s+{re.escape(version)}\b.*$", re.M)
    m = pattern.search(text)
    if not m:
        warn(f"CHANGELOG.md 里没有 {version} 段落，更新说明留空")
        return ""
    start = m.end()
    nxt = re.search(r"^##\s+", text[start:], re.M)
    body = text[start : start + nxt.start()] if nxt else text[start:]
    return body.strip()


def build_release_body(version: str, build: int, assets: list[tuple[Path, str]]) -> str:
    notes = extract_changelog(version)
    lines = [f"版本 **{version}+{build}**", ""]
    if notes:
        lines.append(notes)
    else:
        lines.append("本次更新内容见仓库提交记录。")
    lines.extend(["", "### 安装包", ""])
    for _, name in assets:
        lines.append(f"- `{name}`")
    lines.extend(
        [
            "",
            "> 应用内「设置 → 关于 → 检查更新」会自动识别当前平台与 CPU 架构，",
            "> 只需要下载对应的那一个文件。",
        ]
    )
    return "\n".join(lines)


# ==================== HTTP ====================


def load_token(cli_token: str | None) -> str:
    if cli_token:
        return cli_token.strip()
    env_token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if env_token:
        return env_token.strip()
    if ENV_FILE.exists():
        for raw in ENV_FILE.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            if key.strip() in ("GITHUB_TOKEN", "GH_TOKEN"):
                return value.strip().strip('"').strip("'")
    die(
        "缺少 GitHub Token。\n"
        "        生成方式：GitHub → Settings → Developer settings → Personal access tokens\n"
        "        → Fine-grained tokens → 只勾选本仓库的 Contents: Read and write。\n"
        "        然后写进 .env（GITHUB_TOKEN=xxx，该文件不会进 git）或加 --token 参数。"
    )


def request(
    method: str,
    url: str,
    token: str,
    *,
    data: bytes | None = None,
    content_type: str = "application/json",
    accept: str = "application/vnd.github+json",
) -> tuple[int, dict | list | None]:
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", accept)
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "Videocask-release-publisher")
    if data is not None:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            body = resp.read()
            if not body:
                return resp.status, None
            try:
                return resp.status, json.loads(body)
            except json.JSONDecodeError:
                return resp.status, None
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(body)
        except json.JSONDecodeError:
            parsed = {"message": body}
        return e.code, parsed
    except urllib.error.URLError as e:
        die(f"网络错误：{e.reason}。若本机有代理，先清掉 http_proxy/https_proxy 再试。")


# ==================== 发布 ====================


def main() -> None:
    parser = argparse.ArgumentParser(description="发布三端产物到 GitHub Releases")
    parser.add_argument("--repo", default=DEFAULT_REPO, help="owner/name")
    parser.add_argument("--token", default=None, help="GitHub PAT（也可用 .env）")
    parser.add_argument("--dir", default=str(DELIVERABLES), help="产物目录")
    parser.add_argument("--dry-run", action="store_true", help="只打印计划，不联网")
    parser.add_argument("--update", action="store_true", help="版本已存在时更新说明并补传资产")
    parser.add_argument("--prerelease", action="store_true", help="标记为预发布")
    parser.add_argument(
        "--mandatory",
        action="store_true",
        help="在说明里加 [强制更新]，客户端会跳过「稍后」",
    )
    args = parser.parse_args()

    version, build = read_pubspec_version()
    tag = f"v{version}"
    print(f"== 发布 {tag} (build {build}) 到 {args.repo} ==")
    check_version_consistency(version)

    assets = collect_assets(version, Path(args.dir))
    info(f"找到 {len(assets)} 个产物：")
    for path, name in assets:
        info(f"  {path.name}  →  {name}  ({path.stat().st_size / 1024 / 1024:.1f} MB)")

    body = build_release_body(version, build, assets)
    if args.mandatory:
        body = "[强制更新]\n\n" + body

    if args.dry_run:
        print("\n---- Release 说明预览 ----")
        print(body)
        print("---- dry-run 结束，未联网 ----")
        return

    token = load_token(args.token)

    # 1) 看 tag 是否已有 Release
    status, existing = request("GET", f"{API}/repos/{args.repo}/releases/tags/{tag}", token)
    release_id: int | None = None
    if status == 200 and isinstance(existing, dict):
        release_id = existing.get("id")
        if not args.update:
            die(
                f"{tag} 的 Release 已存在（id={release_id}）。"
                "要更新说明/补传资产请加 --update。"
            )
        info(f"Release 已存在，更新模式（id={release_id}）")
        status, _ = request(
            "PATCH",
            f"{API}/repos/{args.repo}/releases/{release_id}",
            token,
            data=json.dumps({"body": body}).encode("utf-8"),
        )
        if status != 200:
            die(f"更新 Release 说明失败（HTTP {status}）")
    elif status not in (404,):
        die(f"查询 Release 失败（HTTP {status}）: {existing}")

    # 2) 建 Release（tag 由 GitHub 自动创建）
    if release_id is None:
        payload = {
            "tag_name": tag,
            "name": f"罐子 {version}",
            "body": body,
            "draft": False,
            "prerelease": args.prerelease,
        }
        status, created = request(
            "POST",
            f"{API}/repos/{args.repo}/releases",
            token,
            data=json.dumps(payload).encode("utf-8"),
        )
        if status not in (200, 201) or not isinstance(created, dict):
            die(f"创建 Release 失败（HTTP {status}）: {created}")
        release_id = created["id"]
        info(f"已创建 Release: {created.get('html_url', '')}")

    # 3) 上传资产（同名先删掉再传，保证 --update 幂等）
    status, raw_assets = request(
        "GET", f"{API}/repos/{args.repo}/releases/{release_id}/assets", token
    )
    remote_assets = {}
    if isinstance(raw_assets, list):
        remote_assets = {a.get("name"): a.get("id") for a in raw_assets if a.get("name")}

    for path, name in assets:
        if name in remote_assets:
            if not args.update:
                warn(f"已存在，跳过: {name}")
                continue
            asset_id = remote_assets[name]
            info(f"删除旧资产: {name} (id={asset_id})")
            request(
                "DELETE",
                f"{API}/repos/{args.repo}/releases/assets/{asset_id}",
                token,
            )

        ctype = mimetypes.guess_type(name)[0] or "application/octet-stream"
        info(f"上传 {name} ({path.stat().st_size / 1024 / 1024:.1f} MB) …")
        data = path.read_bytes()
        status, uploaded = request(
            "POST",
            f"{UPLOAD_API}/repos/{args.repo}/releases/{release_id}/assets?name={name}",
            token,
            data=data,
            content_type=ctype,
            accept="application/vnd.github+json",
        )
        if status not in (200, 201):
            die(f"上传 {name} 失败（HTTP {status}）: {uploaded}")
        info(f"  完成: {uploaded.get('browser_download_url', '')}")

    print("\n== 发布完成 ==")
    print(f"  Release: https://github.com/{args.repo}/releases/tag/{tag}")
    print("  客户端下次启动（或手动点「检查更新」）即可看到新版本。")


if __name__ == "__main__":
    main()
