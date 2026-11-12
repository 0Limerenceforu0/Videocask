# -*- coding: utf-8 -*-
"""用干净的原生 Windows 环境运行 flutter build windows --release。

背景：从 Git Bash/沙箱环境启动时，MSBuild.exe 立即以 0xC0000005 退出，
疑似 MSYS 注入的环境变量（PATH 中 MSYS 目录、MSYSTEM 等）干扰了
MSBuild/.NET 的启动。本脚本用最小化的标准 Windows 环境变量启动构建，
所有子进程（cmake/msbuild/clang-cl）都继承这份干净环境。
"""

import os
import subprocess
import sys

# 工程根 = 本脚本所在 tool/ 的上一级，仓库搬迁后自动生效；
# 换机或目录结构不同时可用环境变量 VIDEOCASK_PROJECT 覆盖。
PROJECT = os.environ.get(
    "VIDEOCASK_PROJECT",
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
)
WORKSPACE = os.path.dirname(os.path.dirname(PROJECT))
TMP_DIR = os.path.join(WORKSPACE, "_build", "tmp")
os.makedirs(TMP_DIR, exist_ok=True)
FLUTTER_BAT = r"E:\FultterProject\flutter\bin\flutter.bat"

env = {
    "SYSTEMROOT": r"C:\Windows",
    "SystemDrive": "C:",
    "ComSpec": r"C:\Windows\System32\cmd.exe",
    "TEMP": TMP_DIR,
    "TMP": TMP_DIR,
    "PATH": ";".join(
        [
            os.path.join(PROJECT, "tool"),
            r"E:\FultterProject\flutter\bin",
            r"C:\Program Files\Git\cmd",
            r"C:\Windows\System32",
            r"C:\Windows",
            r"C:\Windows\System32\Wbem",
            r"C:\Windows\System32\WindowsPowerShell\v1.0",
        ]
    ),
    "PATHEXT": ".COM;.EXE;.BAT;.CMD",
    "PROGRAMFILES": r"C:\Program Files",
    "ProgramFiles(x86)": r"C:\Program Files (x86)",
    "ProgramData": r"C:\ProgramData",
    "APPDATA": r"C:\Users\Wang\AppData\Roaming",
    "LOCALAPPDATA": r"C:\Users\Wang\AppData\Local",
    "USERPROFILE": r"C:\Users\Wang",
    "USERNAME": "Wang",
    "HOMEDRIVE": "C:",
    "HOMEPATH": r"\Users\Wang",
    "NUMBER_OF_PROCESSORS": "16",
    "PROCESSOR_ARCHITECTURE": "AMD64",
    "OS": "Windows_NT",
    "PUBLIC": r"C:\Users\Public",
    "ALLUSERSPROFILE": r"C:\ProgramData",
    # 固定 pub 缓存到 F 盘：否则 flutter 会退回 %LOCALAPPDATA%\Pub\Cache（C 盘），
    # 重新拉取 libtorrent_flutter（~363MB）且会覆盖掉已打的可选符号补丁。
    "PUB_CACHE": os.environ.get(
        "PUB_CACHE", os.path.join(WORKSPACE, "_build", "pub_cache")
    ),
    # 子脚本（补丁脚本）输出 UTF-8，避免中文在 GBK 控制台下变乱码。
    "PYTHONIOENCODING": "utf-8",
}

cmd = [FLUTTER_BAT, "build", "windows", "--release"]

# 构建前自动补齐 libtorrent_flutter 的「可选符号」补丁：
# 1.9.9 随包发布的 Windows DLL 未导出 lt_set_log_path，而 Dart 绑定会急切
# lookup，导致磁力引擎在 Windows 上永远初始化失败。脚本幂等，已打过则跳过。
patch_script = os.path.join(PROJECT, "tool", "patch_libtorrent_optional_logpath.py")
print("RUN:", sys.executable, patch_script, flush=True)
patch = subprocess.run(
    [sys.executable, patch_script],
    cwd=PROJECT,
    env=env,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    encoding="utf-8",
    errors="replace",
)
print(patch.stdout)
if patch.returncode != 0:
    print("补丁失败，中止构建。", flush=True)
    sys.exit(patch.returncode)

print("RUN:", " ".join(cmd), flush=True)
proc = subprocess.run(
    cmd,
    cwd=PROJECT,
    env=env,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    encoding="utf-8",
    errors="replace",
)
print(proc.stdout)
print("EXIT_CODE =", proc.returncode, flush=True)

# CMake 目标名不支持中文，flutter build 的产物固定叫 movie_app.exe。
# 与 tool/ninja_build.py 保持一致，构建成功后做文件级改名 → 罐子.exe。
# 否则交付的绿色包和应用内更新里都会是 movie_app.exe（对用户暴露内部工程名）。
if proc.returncode == 0:
    bundle = os.path.join(
        PROJECT, "build", "windows", "x64", "runner", "Release"
    )
    for ext in (".exe", ".pdb"):
        src = os.path.join(bundle, "movie_app" + ext)
        if not os.path.exists(src):
            continue
        dst = os.path.join(bundle, "罐子" + ext)
        if os.path.exists(dst):
            os.remove(dst)
        os.replace(src, dst)
        print("已重命名:", os.path.basename(dst), flush=True)

sys.exit(proc.returncode)
