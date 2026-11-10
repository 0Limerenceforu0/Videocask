# -*- coding: utf-8 -*-
"""脱离当前进程树运行 64 位 MSBuild，结果写入文件。

由 WMI/计划任务拉起时，父进程是 WmiPrvSE.exe 等系统进程，
不受 WorkBuddy/Git Bash 进程树环境影响。
"""

import os
import subprocess

MSBUILD = r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\MSBuild.exe"

# 临时目录与结果文件都落在 F 盘工作区，不写 C 盘；工程根按脚本位置自推导。
PROJECT = os.environ.get(
    "VIDEOCASK_PROJECT",
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
)
WORKSPACE = os.path.dirname(os.path.dirname(PROJECT))
TMP_DIR = os.path.join(WORKSPACE, "_build", "tmp")
os.makedirs(TMP_DIR, exist_ok=True)
OUT = os.path.join(WORKSPACE, "_build", "logs", "detached_result.txt")

env = {
    "SYSTEMROOT": r"C:\Windows",
    "TEMP": TMP_DIR,
    "TMP": TMP_DIR,
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
