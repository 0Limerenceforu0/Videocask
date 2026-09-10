# -*- coding: utf-8 -*-
"""测试 VS 内其他可执行文件，缩小崩溃范围。"""

import subprocess

CANDIDATES = [
    r"D:\VS Studio\Community\MSBuild\Current\Bin\MSBuild.exe",  # 32 位
    r"D:\VS Studio\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
    r"D:\VS Studio\Community\Common7\Tools\VsDevCmd.bat",
]

env = {"SYSTEMROOT": r"C:\Windows", "PATH": r"C:\Windows\System32;C:\Windows"}

for exe in CANDIDATES:
    try:
        if exe.endswith(".bat"):
            r = subprocess.run([exe], env=env, capture_output=True, text=True,
                               encoding="utf-8", errors="replace", timeout=60,
                               shell=True)
        else:
            r = subprocess.run([exe, "-version"], env=env, capture_output=True,
                               text=True, encoding="utf-8", errors="replace",
                               timeout=60)
        out = (r.stdout or "").strip().replace("\n", " | ")[:150]
        print(f"{exe}\n  exit={hex(r.returncode)} out={out!r}", flush=True)
    except Exception as e:
        print(f"{exe}\n  EXCEPTION: {e}", flush=True)
