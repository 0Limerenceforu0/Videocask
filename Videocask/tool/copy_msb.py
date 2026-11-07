# -*- coding: utf-8 -*-
"""复制两个 MSBuild.exe 到中立路径以便签名校验。"""

import shutil

X86 = r"D:\VS Studio\Community\MSBuild\Current\Bin\MSBuild.exe"
X64 = r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\MSBuild.exe"
OUT = r"C:\Users\Wang\WorkBuddy\2026-09-08-02-26-53\diag"

shutil.copyfile(X86, OUT + r"\msb32_copy.exe")
shutil.copyfile(X64, OUT + r"\msb64_copy.exe")
print("copied")
