# -*- coding: utf-8 -*-
"""检查系统级加载器相关配置。"""

import winreg


def dump_values(root, path):
    try:
        key = winreg.OpenKey(root, path)
    except OSError as e:
        print(f"[缺失] {path}: {e}")
        return
    print(f"\n=== {path}")
    i = 0
    while True:
        try:
            name, value, vtype = winreg.EnumValue(key, i)
            print(f"  {name} = {value!r}")
            i += 1
        except OSError:
            break


HKLM = winreg.HKEY_LOCAL_MACHINE

# IFEO 根键的值（不是子键！GlobalFlag 常在这里）
dump_values(HKLM, r"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options")

# Session Manager
dump_values(HKLM, r"SYSTEM\CurrentControlSet\Control\Session Manager")

# KnownDLLs
dump_values(HKLM, r"SYSTEM\CurrentControlSet\Control\Session Manager\KnownDLLs")

# .NETFramework 全局配置
dump_values(HKLM, r"SOFTWARE\Microsoft\.NETFramework")

# 用户级 IFEO / .NETFramework
HKCU = winreg.HKEY_CURRENT_USER
dump_values(HKCU, r"SOFTWARE\Microsoft\.NETFramework")
dump_values(HKCU, r"Environment")
