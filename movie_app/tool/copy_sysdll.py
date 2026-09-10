# -*- coding: utf-8 -*-
"""复制系统 ntdll.dll 到中立路径供签名校验。"""

import shutil

OUT = r"C:\Users\Wang\WorkBuddy\2026-09-08-02-26-53\diag"
shutil.copyfile(r"C:\Windows\System32\ntdll.dll", OUT + r"\ntdll_copy.dll")
shutil.copyfile(r"C:\Windows\System32\mscoree.dll", OUT + r"\mscoree_copy.dll")
print("copied")
