# -*- coding: utf-8 -*-
"""预置 media_kit（Predidit 分支）Dart build hook 的原生库缓存。

背景
----
该分支的 build hook 下载 libmpv 后要解压。zip 走纯 Dart，没问题；但
**Windows x64 的包是 7z**，hook 会调外部 `tar` 解压：

    tar -tf <archive>          # 逐行做路径安全校验
    tar -xf <archive> -C <dir>

本机两条路都走不通：
  * Git 自带 GNU tar 1.35 —— 不支持 7z（"This does not look like a tar archive"）
  * Windows 自带 bsdtar 3.5.2 —— libarchive 未编入 LZMA（"LZMA codec is unsupported"）

于是 `flutter test`（主机就是 Windows x64）会卡在 "Building native assets failed"。

本脚本做什么
------------
按 hook 自己的缓存布局，在 `native-cache/<sha256>/` 下准备好：
    archive.<format>   原始包（缺失就从清单 URL 下载，校验 SHA-256）
    files/             解压后的原生库
    extracted.json     每个文件的 SHA-256 校验戳

hook 的 `BundleCache.prepare` 先比对 archive 的 SHA-256，再调 `_validExtraction`
校验 files/ 与 extracted.json；两者都过就直接复用，**根本不会去调 tar**。
所以预置一次之后，Windows 构建与整个测试套件都不再依赖 tar。

缓存目录放在 .dart_tool 之外，因此 `flutter clean` 不会清掉它。

用法
----
    python tool/seed_media_kit_native_cache.py            # 预置全部非 Apple 目标
    python tool/seed_media_kit_native_cache.py windows_x64  # 只预置指定目标
    python tool/seed_media_kit_native_cache.py --force    # 强制重新解压
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import urllib.request
import zipfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
CACHE_DIR = PROJECT / "native-cache"

SEVEN_ZIP_CANDIDATES = [
    Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "7-Zip" / "7z.exe",
    Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "7-Zip" / "7z.exe",
    Path("C:/Program Files/7-Zip/7z.exe"),
]

# Apple 平台包体很大且本项目（Android/Windows/Web）用不到，默认不预置。
SKIP_PREFIXES = ("ios_", "macos_")


def log(msg: str) -> None:
    print(f"[seed] {msg}", flush=True)


def find_seven_zip() -> Path | None:
    for candidate in SEVEN_ZIP_CANDIDATES:
        if candidate.is_file():
            return candidate
    found = shutil.which("7z") or shutil.which("7za")
    return Path(found) if found else None


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_catalog() -> dict:
    """从 .dart_tool/package_config.json 定位 media_kit 包根，读取原生库清单。"""
    config = PROJECT / ".dart_tool" / "package_config.json"
    if not config.is_file():
        raise SystemExit("找不到 .dart_tool/package_config.json，请先跑 flutter pub get")
    packages = json.loads(config.read_text(encoding="utf-8"))["packages"]
    entry = next((p for p in packages if p["name"] == "media_kit"), None)
    if entry is None:
        raise SystemExit("package_config.json 里没有 media_kit")
    catalog = Path(entry["rootUri"]).resolve() / "hook" / "native_bundles.json"
    if not catalog.is_file():
        raise SystemExit(f"找不到原生库清单：{catalog}")
    log(f"清单：{catalog}")
    return json.loads(catalog.read_text(encoding="utf-8"))["bundles"]


def download(url: str, destination: Path) -> None:
    partial = destination.with_suffix(destination.suffix + ".partial")
    log(f"下载 {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "media-kit-build-hook"})
    with urllib.request.urlopen(request, timeout=120) as response, partial.open("wb") as out:
        shutil.copyfileobj(response, out)
    partial.replace(destination)


def extract_7z(seven_zip: Path, archive: Path, destination: Path) -> None:
    # -y 覆盖已有文件；-o<dir> 不带空格以免参数被拆。
    result = subprocess.run(
        [str(seven_zip), "x", "-y", f"-o{destination}", str(archive)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"7z 解压失败({result.returncode})：{result.stderr.strip()}")


def extract_bundle(archive: Path, fmt: str, destination: Path, seven_zip: Path | None) -> None:
    if fmt == "zip":
        with zipfile.ZipFile(archive) as zf:
            zf.extractall(destination)
    elif fmt == "tar.gz":
        with tarfile.open(archive, "r:gz") as tf:
            tf.extractall(destination)
    elif fmt == "7z":
        if seven_zip is None:
            raise RuntimeError("需要 7z，但本机找不到 7z.exe / 7z")
        extract_7z(seven_zip, archive, destination)
    else:
        raise RuntimeError(f"不支持的压缩格式：{fmt}")


def write_stamp(files_dir: Path, stamp_path: Path) -> None:
    """复刻 hook 的 extracted.json：{相对路径: sha256}。"""
    hashes: dict[str, str] = {}
    for path in sorted(files_dir.rglob("*")):
        if path.is_file():
            hashes[path.relative_to(files_dir).as_posix()] = sha256_of(path)
    if not hashes:
        raise RuntimeError(f"解压结果为空：{files_dir}")
    stamp_path.write_text(json.dumps(hashes), encoding="utf-8")


def stamp_is_valid(files_dir: Path, stamp_path: Path) -> bool:
    if not files_dir.is_dir() or not stamp_path.is_file():
        return False
    try:
        hashes = json.loads(stamp_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return False
    if not hashes:
        return False
    for rel, expected in hashes.items():
        path = files_dir / rel
        if not path.is_file() or sha256_of(path) != expected:
            return False
    return True


def seed_target(name: str, bundle: dict, seven_zip: Path | None, force: bool) -> bool:
    fmt = bundle["format"]
    checksum = bundle["sha256"]
    target_dir = CACHE_DIR / checksum
    archive = target_dir / f"archive.{fmt}"
    files_dir = target_dir / "files"
    stamp = target_dir / "extracted.json"

    if not force and stamp_is_valid(files_dir, stamp):
        log(f"{name}: 已就绪（解压产物与校验戳均有效），跳过")
        return True

    target_dir.mkdir(parents=True, exist_ok=True)

    # hook 会先核对 archive 的 SHA-256，缺失/不符就自己下载 —— 我们提前放好它。
    if not archive.is_file() or sha256_of(archive) != checksum:
        download(bundle["url"], archive)
        actual = sha256_of(archive)
        if actual != checksum:
            archive.unlink(missing_ok=True)
            raise RuntimeError(f"{name}: SHA-256 不匹配，期望 {checksum} 实得 {actual}")
    log(f"{name}: 压缩包就绪（{fmt}, {archive.stat().st_size} 字节）")

    if files_dir.exists():
        shutil.rmtree(files_dir)
    staging = target_dir / "extracting"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)

    log(f"{name}: 用 {'7-Zip' if fmt == '7z' else 'Python'} 解压 …")
    extract_bundle(archive, fmt, staging, seven_zip)
    staging.rename(files_dir)
    write_stamp(files_dir, stamp)
    log(f"{name}: 完成，{len(list(files_dir.rglob('*')))} 个条目")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="预置 media_kit 原生库缓存")
    parser.add_argument("targets", nargs="*", help="只预置指定目标（默认全部非 Apple）")
    parser.add_argument("--force", action="store_true", help="强制重新解压")
    parser.add_argument("--include-apple", action="store_true", help="连 Apple 目标一起预置")
    args = parser.parse_args()

    if not CACHE_DIR.is_dir() and not args.targets:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)

    seven_zip = find_seven_zip()
    log(f"7-Zip：{seven_zip or '未找到（仅 7z 包需要）'}")

    bundles = load_catalog()
    names = args.targets or sorted(bundles)
    if not args.include_apple:
        names = [n for n in names if not n.startswith(SKIP_PREFIXES)]
    if not names:
        log("没有要预置的目标")
        return 0

    failures: list[tuple[str, str]] = []
    for name in names:
        bundle = bundles.get(name)
        if bundle is None:
            log(f"{name}: 清单里没有这个目标，跳过")
            continue
        try:
            seed_target(name, bundle, seven_zip, args.force)
        except Exception as exc:  # noqa: BLE001 - 逐个目标独立失败更好排查
            log(f"{name}: 失败 —— {exc}")
            failures.append((name, str(exc)))

    if failures:
        log("")
        log("以下目标未就绪（构建对应平台时会失败）：")
        for name, reason in failures:
            log(f"  - {name}: {reason}")
        # 非 Apple 目标失败才算阻断：Apple 只是没预置，不影响本项目三端构建。
        blocking = [n for n, _ in failures if not n.startswith(SKIP_PREFIXES)]
        return 1 if blocking else 0

    log("")
    log(f"全部就绪，缓存位于 {CACHE_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())