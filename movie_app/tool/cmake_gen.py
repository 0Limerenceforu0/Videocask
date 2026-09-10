# -*- coding: utf-8 -*-
"""手动驱动 Windows 构建：
1. 设置 VCTargetsPath 环境变量，避免 cmake 运行(崩溃的)64位 MSBuild 探测。
2. 用 32 位 MSBuild.exe 编译 x64 Release 解决方案。
"""

import subprocess
import sys

PROJECT = r"D:\flutter-dome\movie_app\movie_app"
CMAKE = (
    r"D:\VS Studio\Community\Common7\IDE\CommonExtensions\Microsoft\CMake"
    r"\CMake\bin\cmake.exe"
)
MSBUILD_X86 = r"D:\VS Studio\Community\MSBuild\Current\Bin\MSBuild.exe"
VCTARGETS = r"D:\VS Studio\Community\MSBuild\Microsoft\VC\v170"

env = {
    "SYSTEMROOT": r"C:\Windows",
    "TEMP": r"C:\Users\Wang\AppData\Local\Temp",
    "TMP": r"C:\Users\Wang\AppData\Local\Temp",
    "PATH": ";".join([
        r"D:\flutter-dome\movie_app\movie_app\tool",
        r"E:\FultterProject\flutter\bin",
        r"C:\Program Files\Git\cmd",
        r"C:\Windows\System32",
        r"C:\Windows",
        r"C:\Windows\System32\Wbem",
    ]),
    "PATHEXT": ".COM;.EXE;.BAT;.CMD",
    "PROGRAMFILES": r"C:\Program Files",
    "ProgramData": r"C:\ProgramData",
    "APPDATA": r"C:\Users\Wang\AppData\Roaming",
    "LOCALAPPDATA": r"C:\Users\Wang\AppData\Local",
    "USERPROFILE": r"C:\Users\Wang",
    "USERNAME": "Wang",
    "HOMEDRIVE": "C:",
    "HOMEPATH": r"\Users\Wang",
    "OS": "Windows_NT",
    # 关键：预设 VCTargetsPath，看 cmake 是否因此跳过 MSBuild 探测
    "VCTargetsPath": VCTARGETS + "\\",
    # 顺带把 VS 的工具链变量也预设，提高成功率
    "VCINSTALLDIR": "D:\\VS Studio\\Community\\VC\\",
    "VSINSTALLDIR": "D:\\VS Studio\\Community\\",
    # Flutter windows CMake 脚本必需
    "FLUTTER_ROOT": r"E:\FultterProject\flutter",
    "PROGRAMFILES(X86)": r"C:\Program Files (x86)",
    "PROCESSOR_ARCHITECTURE": "AMD64",
    "NUMBER_OF_PROCESSORS": "8",
    "COMSPEC": r"C:\Windows\system32\cmd.exe",
    "LANG": "en_US.UTF-8",
}

steps = [
    ("cmake 配置", [
        CMAKE,
        "-S", PROJECT + r"\windows",
        "-B", PROJECT + r"\build\windows\x64",
        "-G", "Visual Studio 17 2022",
        "-A", "x64",
        "-DFLUTTER_TARGET_PLATFORM=windows-x64",
    ]),
]

for label, cmd in steps:
    print(f"=== {label}: {' '.join(cmd)}", flush=True)
    r = subprocess.run(
        cmd, cwd=PROJECT, env=env, capture_output=True, text=True,
        encoding="utf-8", errors="replace",
    )
    print(r.stdout[-3000:])
    print(r.stderr[-2000:])
    print(f"exit={r.returncode}", flush=True)
    if r.returncode != 0:
        sys.exit(1)
