# -*- coding: utf-8 -*-
"""测试其他 EP=0 IL-only exe 是否同样崩溃。"""

import subprocess

env = {"SYSTEMROOT": r"C:\Windows", "PATH": r"C:\Windows\System32;C:\Windows"}

CANDIDATES = [
    r"D:\VS Studio\Community\Common7\IDE\MSTest64.exe",
    r"D:\VS Studio\Community\Common7\IDE\PerfWatson2.exe",
    r"D:\VS Studio\Community\Common7\IDE\Extensions\TestPlatform\testhost.exe",
    r"D:\VS Studio\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\TF.exe",
]

for exe in CANDIDATES:
    try:
        r = subprocess.run(
            [exe], env=env, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=20,
        )
        out = ((r.stdout or "") + (r.stderr or "")).strip().replace("\n", " | ")[:100]
        print(f"{exe.split(chr(92))[-1]}: exit=0x{r.returncode:X} {out!r}")
    except subprocess.TimeoutExpired:
        print(f"{exe.split(chr(92))[-1]}: TIMEOUT — 进程存活(正常)")
    except Exception as e:
        print(f"{exe.split(chr(92))[-1]}: EXCEPTION {e}")
