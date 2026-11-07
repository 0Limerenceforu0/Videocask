# -*- coding: utf-8 -*-
"""检查 IFEO（Image File Execution Options）中与 MSBuild 相关的注册表配置。"""

import winreg

paths = [
    (r"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options",
     winreg.HKEY_LOCAL_MACHINE),
    (r"SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options",
     winreg.HKEY_LOCAL_MACHINE),
]

for subpath, root in paths:
    try:
        key = winreg.OpenKey(root, subpath)
    except OSError as e:
        print(f"open {subpath}: {e}")
        continue
    names = []
    i = 0
    while True:
        try:
            names.append(winreg.EnumKey(key, i))
            i += 1
        except OSError:
            break
    hits = [n for n in names if "msbuild" in n.lower()]
    print(f"\n{subpath}: {len(names)} 个子键, MSBuild 相关: {hits}")
    for h in hits:
        try:
            hk = winreg.OpenKey(key, h)
        except OSError:
            continue
        j = 0
        while True:
            try:
                name, value, vtype = winreg.EnumValue(hk, j)
                print(f"  [{h}] {name} = {value!r} (type={vtype})")
                j += 1
            except OSError:
                break
        # 检查子键（如 msbuild.exe 下的 filter）
        k = 0
        while True:
            try:
                sub = winreg.EnumKey(hk, k)
                print(f"  [{h}] 子键: {sub}")
                k += 1
            except OSError:
                break
