# -*- coding: utf-8 -*-
"""对比 Bin 与 Bin\amd64 目录内容，找出 64 位版独有/缺失的依赖。"""

import hashlib
import os

BIN = r"D:\VS Studio\Community\MSBuild\Current\Bin"
AMD = os.path.join(BIN, "amd64")


def sha16(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()[:16]


bin_files = {}
for root, dirs, files in os.walk(BIN):
    dirs[:] = [d for d in dirs if d.lower() != "amd64"]
    for name in files:
        p = os.path.join(root, name)
        rel = os.path.relpath(p, BIN)
        bin_files[rel] = p

amd_files = {}
for root, dirs, files in os.walk(AMD):
    for name in files:
        p = os.path.join(root, name)
        rel = os.path.relpath(p, AMD)
        amd_files[rel] = p

print("=== amd64 目录内容 ===", flush=True)
for rel in sorted(amd_files):
    p = amd_files[rel]
    size = os.path.getsize(p)
    print(f"  {rel}  ({size}b)", flush=True)

print(f"\nBin(不含amd64) 文件数={len(bin_files)}, amd64 文件数={len(amd_files)}", flush=True)

# 同名文件哈希对比（检出损坏副本）
diff = []
for rel, amd_path in amd_files.items():
    bin_path = os.path.join(BIN, rel)
    if os.path.exists(bin_path):
        if sha16(amd_path) != sha16(bin_path):
            diff.append(rel)
print("同名但哈希不同:", diff or "无", flush=True)
