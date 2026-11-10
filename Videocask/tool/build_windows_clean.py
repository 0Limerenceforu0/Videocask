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
}

cmd = [FLUTTER_BAT, "build", "windows", "--release"]
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
sys.exit(proc.returncode)
