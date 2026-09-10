# -*- coding: utf-8 -*-
"""诊断 MSBuild.exe 启动崩溃问题。

依次尝试多种环境组合运行 MSBuild -version，记录退出码与输出。
"""

import subprocess

MSBUILD = r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\MSBuild.exe"

clean_env = {
    "SYSTEMROOT": r"C:\Windows",
    "TEMP": r"C:\Users\Wang\AppData\Local\Temp",
    "TMP": r"C:\Users\Wang\AppData\Local\Temp",
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
