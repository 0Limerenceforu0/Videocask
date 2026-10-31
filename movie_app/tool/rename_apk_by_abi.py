#!/usr/bin/env python3
"""把打包出来的 APK 按 ABI 改成中文友好文件名，放进 deliverables。

用法：
    python tool/rename_apk_by_abi.py

流程：
  1) 优先从 build/app/outputs/flutter-apk/app-<abi>-release.apk 复制并直接命名
     （split-per-abi 的产物），已存在的同名文件会被覆盖。
  2) 若 build 产物不存在，则回退：把 deliverables 里已有的
     movie_app_android_*.apk 就地改名（兼容旧流程）。
"""
import re
import sys
from pathlib import Path

# ABI 片段 -> 中文标签（从长到短匹配，避免 x86 命中 x86_64）
ABI_LABELS = [
    ("armeabi-v7a", "安卓32位_armeabi-v7a"),
    ("arm64-v8a", "安卓64位_arm64-v8a"),
    ("arm64", "安卓64位_arm64-v8a"),
    ("x86_64", "模拟器64位_x86_64"),
    ("x86", "模拟器32位_x86"),
]

APP_NAME = "高清影视"
BUILD_APK_DIR = Path("build/app/outputs/flutter-apk")


def label_for_abi(name: str) -> str | None:
    """从文件名里识别 ABI，返回中文标签。"""
    lower = name.lower()
    for token, label in ABI_LABELS:
        # 用分隔符边界匹配，避免 arm64 误命中 arm64-v8a 之外的场景
        if re.search(r"(?<![a-z0-9])" + re.escape(token.lower()) + r"(?![a-z0-9])", lower):
            return label
    return None


def copy_from_build(project_root: Path, deliverables: Path) -> list[Path]:
    """从 gradle 产物复制并直接命名成中文名（覆盖旧文件）。"""
    build_dir = project_root / BUILD_APK_DIR
    if not build_dir.exists():
        return []
    produced: list[Path] = []
    for src in sorted(build_dir.glob("app-*-release.apk")):
        label = label_for_abi(src.name)
        if not label:
            print(f"跳过：无法识别 ABI — {src.name}", file=sys.stderr)
            continue
        dst = deliverables / f"{APP_NAME}_{label}.apk"
        dst.write_bytes(src.read_bytes())
        size_mb = src.stat().st_size / 1024 / 1024
        print(f"{src.name} -> {dst.name}  ({size_mb:.1f} MB)")
        produced.append(dst)
    return produced


def rename_existing(deliverables: Path) -> list[Path]:
    """回退方案：就地改名 deliverables 里已有的 movie_app_android_*.apk。"""
    renamed: list[Path] = []
    for old in sorted(deliverables.glob("movie_app_android_*.apk")):
        label = label_for_abi(old.name)
        if not label:
            print(f"跳过：无法识别 ABI — {old.name}", file=sys.stderr)
            continue
        new = old.with_name(f"{APP_NAME}_{label}.apk")
        if new.exists():
            print(f"跳过：目标已存在 — {new.name}", file=sys.stderr)
            continue
        old.rename(new)
        print(f"{old.name} -> {new.name}")
        renamed.append(new)
    return renamed


def main() -> int:
    project_root = Path(__file__).resolve().parent.parent
    deliverables = project_root / "deliverables"
    if not deliverables.exists():
        print(f"目录不存在：{deliverables}", file=sys.stderr)
        return 1

    produced = copy_from_build(project_root, deliverables)
    if produced:
        print(f"\n完成：{len(produced)} 个 APK 已更新。")
        return 0

    renamed = rename_existing(deliverables)
    if renamed:
        print(f"\n完成：就地改名 {len(renamed)} 个 APK。")
        return 0

    print("没有可处理的 APK。先跑 flutter build apk --release --split-per-abi。",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
