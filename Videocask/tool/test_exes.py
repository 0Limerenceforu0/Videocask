# -*- coding: utf-8 -*-
"""测试多个 64 位原生 exe 的启动情况。"""

import glob
import os
import subprocess

CANDIDATES = [
    r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\Tracker.exe",
    r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\MSBuildTaskHost.exe",
]

# 找 cl.exe
for pat in [
    r"D:\VS Studio\Community\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
]:
    CANDIDATES.extend(sorted(glob.glob(pat))[-1:])

env = {"SYSTEMROOT": r"C:\Windows", "PATH": r"C:\Windows\System32;C:\Windows"}

for exe in CANDIDATES:
    if not os.path.exists(exe):
        print(f"SKIP (不存在): {exe}")
        continue
    try:
        r = subprocess.run(
            [exe], env=env, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=30,
        )
        out = (r.stdout or r.stderr or "").strip().replace("\n", " | ")[:120]
        print(f"{os.path.basename(exe)}: exit=0x{r.returncode:X} {out!r}")
    except subprocess.TimeoutExpired:
        print(f"{os.path.basename(exe)}: TIMEOUT (30s) — 进程存活未崩溃")
    except Exception as e:
        print(f"{os.path.basename(exe)}: EXCEPTION {e}")
