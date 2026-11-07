# -*- coding: utf-8 -*-
"""脱离当前进程树运行 64 位 MSBuild，结果写入文件。

由 WMI/计划任务拉起时，父进程是 WmiPrvSE.exe 等系统进程，
不受 WorkBuddy/Git Bash 进程树环境影响。
"""

import subprocess

MSBUILD = r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\MSBuild.exe"
OUT = r"C:\Users\Wang\WorkBuddy\2026-09-08-02-26-53\diag\detached_result.txt"

env = {
    "SYSTEMROOT": r"C:\Windows",
    "TEMP": r"C:\Users\Wang\AppData\Local\Temp",
    "TMP": r"C:\Users\Wang\AppData\Local\Temp",
    "PATH": r"C:\Windows\System32;C:\Windows",
}

try:
    r = subprocess.run(
        [MSBUILD, "-version", "-nologo"],
        env=env, capture_output=True, text=True, encoding="utf-8",
        errors="replace", timeout=120,
    )
    result = (
        f"exit=0x{r.returncode:X}\nstdout={r.stdout.strip()[:300]}\n"
        f"stderr={r.stderr.strip()[:300]}\n"
    )
except Exception as e:
    result = f"exception={e}\n"

with open(OUT, "w", encoding="utf-8") as f:
    f.write(result)
