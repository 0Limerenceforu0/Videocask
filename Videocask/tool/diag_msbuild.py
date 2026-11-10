# -*- coding: utf-8 -*-
"""诊断 MSBuild.exe 启动崩溃问题。

依次尝试多种环境组合运行 MSBuild -version，记录退出码与输出。
"""

import os
import subprocess

MSBUILD = r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\MSBuild.exe"

# 临时目录落在 F 盘工作区，不写 C 盘；工程根按脚本位置自推导。
PROJECT = os.environ.get(
    "VIDEOCASK_PROJECT",
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
)
WORKSPACE = os.path.dirname(os.path.dirname(PROJECT))
TMP_DIR = os.path.join(WORKSPACE, "_build", "tmp")
os.makedirs(TMP_DIR, exist_ok=True)

clean_env = {
    "SYSTEMROOT": r"C:\Windows",
    "TEMP": TMP_DIR,
    "TMP": TMP_DIR,
    "PATH": r"C:\Windows\System32;C:\Windows",
    "PATHEXT": ".COM;.EXE;.BAT;.CMD",
    "PROGRAMFILES": r"C:\Program Files",
}

cases = {
    "clean_env": clean_env,
    "minimal_env": {"SYSTEMROOT": r"C:\Windows"},
    "full_env_no_path_change": None,  # 继承完整当前环境
}

for name, env in cases.items():
    try:
        r = subprocess.run(
            [MSBUILD, "-version", "-nologo"],
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=60,
        )
        out = (r.stdout or "").strip().replace("\n", " | ")[:200]
        err = (r.stderr or "").strip().replace("\n", " | ")[:200]
        print(f"[{name}] exit={hex(r.returncode)} stdout={out!r} stderr={err!r}", flush=True)
    except Exception as e:
        print(f"[{name}] EXCEPTION: {e}", flush=True)
