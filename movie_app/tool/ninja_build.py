# -*- coding: utf-8 -*-
"""用 Ninja 生成器构建 Windows Release，彻底绕开崩溃的 64 位 MSBuild。

用法:
  python tool/ninja_build.py configure   # 仅配置
  python tool/ninja_build.py build       # 配置 + 编译 + 安装 bundle
"""

import subprocess
import sys
import shutil
import os

PROJECT = r"D:\flutter-dome\movie_app\movie_app"
CMAKE = (
    r"D:\VS Studio\Community\Common7\IDE\CommonExtensions\Microsoft\CMake"
    r"\CMake\bin\cmake.exe"
)
MSVC = r"D:\VS Studio\Community\VC\Tools\MSVC\14.43.34808"
SDK = r"D:\Windows Kits\10"
SDKVER = "10.0.22621.0"
NINJA_DIR = (
    r"D:\VS Studio\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"
)
BUILD_DIR = PROJECT + r"\build\windows\x64_ninja"
OUT_DIR = BUILD_DIR + r"\bundle"

env = {
    "SYSTEMROOT": r"C:\Windows",
    "TEMP": r"C:\Users\Wang\AppData\Local\Temp",
    "TMP": r"C:\Users\Wang\AppData\Local\Temp",
    "PATH": ";".join([
        MSVC + r"\bin\Hostx64\x64",
        SDK + r"\bin\\" + SDKVER + r"\x64",   # rc.exe / mt.exe / midlrt
        NINJA_DIR,
        PROJECT + r"\tool",                 # nuget.exe
        r"E:\FultterProject\flutter\bin",    # flutter tool
        r"C:\Program Files\Git\cmd",         # git
        r"C:\Windows\System32",
        r"C:\Windows",
        r"C:\Windows\System32\Wbem",
        r"C:\Windows\System32\WindowsPowerShell\v1.0",  # flutter tool 需要 powershell
    ]),
    "PATHEXT": ".COM;.EXE;.BAT;.CMD",
    "PROGRAMFILES": r"C:\Program Files",
    "PROGRAMFILES(X86)": r"C:\Program Files (x86)",
    "ProgramData": r"C:\ProgramData",
    "APPDATA": r"C:\Users\Wang\AppData\Roaming",
    "LOCALAPPDATA": r"C:\Users\Wang\AppData\Local",
    "USERPROFILE": r"C:\Users\Wang",
    "USERNAME": "Wang",
    "HOMEDRIVE": "C:",
    "HOMEPATH": r"\Users\Wang",
    "OS": "Windows_NT",
    "PROCESSOR_ARCHITECTURE": "AMD64",
    "NUMBER_OF_PROCESSORS": "8",
    "COMSPEC": r"C:\Windows\system32\cmd.exe",
    "LANG": "en_US.UTF-8",
    "FLUTTER_ROOT": r"E:\FultterProject\flutter",
    # MSVC 编译环境
    "INCLUDE": ";".join([
        MSVC + r"\include",
        SDK + r"\Include\\" + SDKVER + r"\ucrt",
        SDK + r"\Include\\" + SDKVER + r"\um",
        SDK + r"\Include\\" + SDKVER + r"\shared",
        SDK + r"\Include\\" + SDKVER + r"\winrt",
        SDK + r"\Include\\" + SDKVER + r"\cppwinrt",
    ]),
    "LIB": ";".join([
        MSVC + r"\lib\x64",
        SDK + r"\Lib\\" + SDKVER + r"\ucrt\x64",
        SDK + r"\Lib\\" + SDKVER + r"\um\x64",
    ]),
    "LIBPATH": MSVC + r"\lib\x64",
    "VCToolsInstallDir": MSVC + "\\",
    "WindowsSdkDir": SDK + "\\",
    "WindowsSDKVersion": SDKVER + "\\",
}

CONFIGURE_CMD = [
    CMAKE,
    "-S", PROJECT + r"\windows",
    "-B", BUILD_DIR,
    "-G", "Ninja",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_C_COMPILER=cl.exe",
    "-DCMAKE_CXX_COMPILER=cl.exe",
    "-DFLUTTER_TARGET_PLATFORM=windows-x64",
    "-DCMAKE_INSTALL_PREFIX=" + OUT_DIR,
]


def run(label, cmd, cwd=PROJECT):
    print(f"=== {label}: {' '.join(cmd)}", flush=True)
    r = subprocess.run(
        cmd, cwd=cwd, env=env, capture_output=True, text=True,
        encoding="utf-8", errors="replace",
    )
    if r.stdout:
        print(r.stdout[-4000:])
    if r.stderr:
        print(r.stderr[-3000:])
    print(f"exit={r.returncode}", flush=True)
    return r.returncode


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "build"
    if run("cmake configure", CONFIGURE_CMD) != 0:
        sys.exit(1)
    if mode == "configure":
        return
    if run("cmake build", [CMAKE, "--build", BUILD_DIR, "--parallel", "8"]) != 0:
        sys.exit(1)
    if run("cmake install", [CMAKE, "--install", BUILD_DIR, "--config", "Release"]) != 0:
        sys.exit(1)
    # 汇总 bundle 内容
    if os.path.isdir(OUT_DIR):
        print("\n=== bundle 内容 ===")
        for root, dirs, files in os.walk(OUT_DIR):
            rel = os.path.relpath(root, OUT_DIR)
            for f in files:
                p = os.path.join(root, f)
                print(f"{rel}\\{f}  {os.path.getsize(p)}")
    else:
        print("!! 未找到输出目录:", OUT_DIR)


if __name__ == "__main__":
    main()
