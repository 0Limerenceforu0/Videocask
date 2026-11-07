"""修复 windows/flutter/ephemeral —— 让 `flutter build windows` 跳过也能编出 Release。

背景
----
`flutter build windows` 会在构建前把两样东西塞进 `windows/flutter/ephemeral/`：

1. **Flutter 引擎产物**：`flutter_windows.dll(.lib/.exp)`、5 个 C 头文件、
   `icudtl.dat`、`cpp_client_wrapper/`
2. **各插件的 symlink**：`.plugin_symlinks/<plugin> -> pub-cache 里的插件目录`

一旦 ephemeral 被误删（比如执行过 `flutter clean` 后又手工删目录），或者
flutter 工具链本身跑不起来（沙箱里 `reg.exe` / `wmic.exe` 被拦截导致
doctor 崩溃），cmake 就会报：

    ninja: error: '.../ephemeral/flutter_windows.dll.lib', missing and no known rule to make it

本脚本不依赖 flutter 工具，直接把这两样东西补齐，之后再跑
`python tool/ninja_build.py build` 即可。

另外 media_kit 的 `mpv-dev` / `ANGLE` 两个 7z 在很多环境下载得到、但 cmake 的
自定义解压目标跑不出内容（目录留空），导致
`libmpv/libmpv.dll.a missing`，这里也一并手工解包。

用法
----
    python tool/windows_ephemeral_repair.py
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
EPHEMERAL = PROJECT_ROOT / "windows" / "flutter" / "ephemeral"
SYMLINKS = EPHEMERAL / ".plugin_symlinks"
BUILD_DIR = PROJECT_ROOT / "build" / "windows" / "x64_ninja"

# cmake 的 tar 解压目标生成的目录
LIBMPV_SRC = BUILD_DIR / "libmpv"
ANGLE_SRC = BUILD_DIR / "ANGLE"
LIBMPV_ARCHIVE = BUILD_DIR / "mpv-dev-x86_64-20230924-git-652a1dd.7z"
ANGLE_ARCHIVE = BUILD_DIR / "ANGLE.7z"

# 引擎头文件（release / debug 两份 artifact 里同名同内容）
ENGINE_HEADERS = (
    "flutter_export.h",
    "flutter_messenger.h",
    "flutter_plugin_registrar.h",
    "flutter_texture_registrar.h",
    "flutter_windows.h",
)
# 只有 release artifact 里有的链接产物
ENGINE_RELEASE_BINARIES = (
    "flutter_windows.dll",
    "flutter_windows.dll.lib",
    "flutter_windows.dll.exp",
)


def log(msg: str) -> None:
    print(msg, flush=True)


def find_flutter_root() -> Path:
    """优先读 generated_config.cmake 里的 FLUTTER_ROOT，其次问 `where flutter`。"""
    config = EPHEMERAL / "generated_config.cmake"
    if config.exists():
        for line in config.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = line.strip()
            if line.startswith("file(TO_CMAKE_PATH") and "FLUTTER_ROOT" in line:
                parts = line.split('"')
                if len(parts) >= 2:
                    return Path(parts[1])

    proc = subprocess.run(
        ["where", "flutter"], capture_output=True, text=True, shell=True
    )
    if proc.returncode == 0:
        first = proc.stdout.strip().splitlines()[0].strip()
        # <root>/bin/flutter.bat → <root>
        return Path(first).resolve().parent.parent
    raise SystemExit(
        "[!] 找不到 Flutter SDK：要么先跑一次 flutter 命令生成 "
        "generated_config.cmake，要么把 flutter 加进 PATH。"
    )


def repair_plugin_symlinks() -> int:
    """按 .flutter-plugins-dependencies 补齐 Windows 插件 symlink。"""
    deps = PROJECT_ROOT / ".flutter-plugins-dependencies"
    if not deps.exists():
        log("[!] 没有 .flutter-plugins-dependencies，跳过 symlink 修复（先跑 flutter pub get）")
        return 0

    data = json.loads(deps.read_text(encoding="utf-8"))
    plugins = data.get("plugins", {}).get("windows", []) or []
    SYMLINKS.mkdir(parents=True, exist_ok=True)

    created = skipped = failed = 0
    for plugin in plugins:
        if not plugin.get("native_build", False):
            continue
        name = plugin["name"]
        src = Path(plugin["path"])
        link = SYMLINKS / name
        if link.exists() or link.is_symlink():
            skipped += 1
            continue
        if not src.exists():
            log(f"  [x] {name}: 源目录不存在 {src}")
            failed += 1
            continue
        try:
            link.symlink_to(src, target_is_directory=True)
            created += 1
        except OSError as exc:  # 无开发者模式 / 无管理员权限时 Windows 会拒绝
            log(f"  [x] {name}: symlink 失败 {exc}")
            failed += 1

    log(f"[*] 插件 symlink：新建 {created}，已存在 {skipped}，失败 {failed}")
    if failed:
        log("    提示：Windows 创建 symlink 需要「开发者模式」或管理员权限。")
    return failed


def repair_engine_artifacts(flutter_root: Path) -> int:
    """把引擎产物从 SDK 的 artifact 缓存拷到 ephemeral。"""
    engine_dir = flutter_root / "bin" / "cache" / "artifacts" / "engine"
    release = engine_dir / "windows-x64-release"
    debug = engine_dir / "windows-x64"
    if not release.exists():
        log(f"[!] 引擎 artifact 目录不存在：{release}")
        return 1

    EPHEMERAL.mkdir(parents=True, exist_ok=True)
    copied = 0
    for name in ENGINE_RELEASE_BINARIES:
        src = release / name
        if src.exists():
            shutil.copy2(src, EPHEMERAL / name)
            copied += 1
    for name in ENGINE_HEADERS:
        src = release / name if (release / name).exists() else debug / name
        if src.exists():
            shutil.copy2(src, EPHEMERAL / name)
            copied += 1

    # icudtl.dat 只在 debug artifact 里
    icu = debug / "icudtl.dat"
    if icu.exists():
        shutil.copy2(icu, EPHEMERAL / "icudtl.dat")
        copied += 1

    # C++ client wrapper（flutter/ 下 CMakeLists 会 add_subdirectory 它）
    wrapper_src = debug / "cpp_client_wrapper"
    wrapper_dst = EPHEMERAL / "cpp_client_wrapper"
    if wrapper_src.exists() and not wrapper_dst.exists():
        shutil.copytree(wrapper_src, wrapper_dst)
        copied += 1

    log(f"[*] 引擎产物：拷贝 {copied} 项 → {EPHEMERAL}")
    return 0


def _find_cmake() -> str:
    """找 cmake.exe：PATH → tool/ninja_build.py 里写死的那份 → 全盘扫 VS 自带那份。"""
    found = shutil.which("cmake")
    if found:
        return found

    # ninja_build.py 里已经写死了本机的 VS 路径，直接复用
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import ninja_build  # type: ignore

        candidate = Path(ninja_build.CMAKE)
        if candidate.exists():
            return str(candidate)
    except Exception:
        pass

    for drive in ("C:", "D:", "E:"):
        root = Path(drive + "\\")
        if not root.exists():
            continue
        for hit in sorted(
            root.glob("*/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe")
        ):
            return str(hit)
    raise SystemExit("[!] 找不到 cmake.exe，无法解包 mpv / ANGLE。")


def _extract(cmake: str, archive: Path, dest: Path) -> bool:
    """用 `cmake -E tar xzf` 解 7z（libarchive 支持 7zip），解完目录非空即成功。"""
    if not archive.exists() or archive.stat().st_size == 0:
        return False
    if dest.exists() and any(dest.iterdir()):
        return True
    dest.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        [cmake, "-E", "tar", "xzf", str(archive)],
        cwd=str(dest),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        log(f"  [x] 解压失败 {archive.name}: {proc.stderr.strip()}")
        return False
    return any(dest.iterdir())


def repair_media_kit_archives() -> int:
    """解包 mpv-dev / ANGLE，并把 libmpv/include/mpv 提升为 libmpv/include。"""
    if not BUILD_DIR.exists():
        return 0

    cmake = _find_cmake()
    ok = True

    if _extract(cmake, LIBMPV_ARCHIVE, LIBMPV_SRC):
        # media_kit 的 CMakeLists 期望 libmpv/include/*.h，
        # 而原始 7z 里是 libmpv/include/mpv/*.h，需要拍平一层。
        nested = LIBMPV_SRC / "include" / "mpv"
        if nested.is_dir():
            tmp = LIBMPV_SRC / "_mpv_include_tmp"
            if tmp.exists():
                shutil.rmtree(tmp)
            nested.rename(tmp)
            shutil.rmtree(LIBMPV_SRC / "include")
            tmp.rename(LIBMPV_SRC / "include")
        log(f"[*] libmpv 就绪：{LIBMPV_SRC}")
    elif (LIBMPV_SRC / "libmpv.dll.a").exists():
        log("[*] libmpv 已就绪，跳过")
    else:
        log(f"[!] 缺 {LIBMPV_ARCHIVE.name}（或为空），media_kit 会链接失败")
        ok = False

    if _extract(cmake, ANGLE_ARCHIVE, ANGLE_SRC):
        log(f"[*] ANGLE 就绪：{ANGLE_SRC}")
    elif (ANGLE_SRC / "libEGL.dll").exists():
        log("[*] ANGLE 已就绪，跳过")
    else:
        log(f"[!] 缺 {ANGLE_ARCHIVE.name}（或为空）")
        ok = False

    return 0 if ok else 1


def main() -> int:
    log("=== movie_app Windows ephemeral 修复 ===")
    flutter_root = find_flutter_root()
    log(f"[*] Flutter SDK: {flutter_root}")

    failed = repair_plugin_symlinks()
    failed += repair_engine_artifacts(flutter_root)
    failed += repair_media_kit_archives()

    if failed:
        log("\n[!] 修复未完成，看上面 [x] 条目")
        return 1
    log("\n[✓] ephemeral 就绪，可以跑了：python tool\\ninja_build.py build")
    return 0


if __name__ == "__main__":
    sys.exit(main())
