# -*- coding: utf-8 -*-
"""对比 32/64 位 MSBuild，并测试从中立路径运行 64 位版。"""

import hashlib
import os
import shutil
import subprocess

X86 = r"D:\VS Studio\Community\MSBuild\Current\Bin\MSBuild.exe"
X64 = r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\MSBuild.exe"
TMP = r"C:\Users\Wang\WorkBuddy\2026-09-08-02-26-53\diag"

os.makedirs(TMP, exist_ok=True)

for label, src in [("x86", X86), ("x64", X64)]:
    with open(src, "rb") as f:
        data = f.read()
    h = hashlib.sha256(data).hexdigest()[:16]
    print(f"{label}: size={len(data)} sha256={h}", flush=True)

# 从中立路径运行 64 位版（排除原路径因素，如空格/权限）
dst = os.path.join(TMP, "msb64.exe")
shutil.copyfile(X64, dst)
env = {"SYSTEMROOT": r"C:\Windows", "PATH": r"C:\Windows\System32;C:\Windows"}
r = subprocess.run([dst, "-version", "-nologo"], env=env, capture_output=True,
                   text=True, encoding="utf-8", errors="replace", timeout=60)
print(f"copy-run: exit={hex(r.returncode)} out={(r.stdout or '').strip()[:80]!r}", flush=True)

# 检查 PE 头：是否真是 64 位
with open(X64, "rb") as f:
    header = f.read(4096)
pe_off = int.from_bytes(header[0x3C:0x40], "little")
machine = int.from_bytes(header[pe_off + 4:pe_off + 6], "little")
print(f"x64 PE machine=0x{machine:X} (8664=AMD64, 14C=i386)", flush=True)
with open(X86, "rb") as f:
    header86 = f.read(4096)
pe_off86 = int.from_bytes(header86[0x3C:0x40], "little")
machine86 = int.from_bytes(header86[pe_off86 + 4:pe_off86 + 6], "little")
print(f"x86 PE machine=0x{machine86:X} (8664=AMD64, 14C=i386)", flush=True)
