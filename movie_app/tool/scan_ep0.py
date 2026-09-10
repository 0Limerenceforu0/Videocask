# -*- coding: utf-8 -*-
"""扫描 VS 安装目录中 EP=0 且无导入表的 exe，并测试可运行性。"""

import os
import struct
import subprocess

ROOT = r"D:\VS Studio\Community"
env = {"SYSTEMROOT": r"C:\Windows", "PATH": r"C:\Windows\System32;C:\Windows"}


def pe_info(path):
    try:
        with open(path, "rb") as f:
            head = f.read(0x400)
        if head[:2] != b"MZ":
            return None
        e_lfanew = struct.unpack_from("<I", head, 0x3C)[0]
        if head[e_lfanew:e_lfanew + 4] != b"PE\0\0":
            return None
        nsec = struct.unpack_from("<H", head, e_lfanew + 6)[0]
        opt_size = struct.unpack_from("<H", head, e_lfanew + 20)[0]
        opt_off = e_lfanew + 24
        if opt_off + 24 > len(head):
            return None
        magic = struct.unpack_from("<H", head, opt_off)[0]
        ep = struct.unpack_from("<I", head, opt_off + 16)[0]
        machine = struct.unpack_from("<H", head, e_lfanew + 4)[0]
        base_dir = opt_off + (112 if magic == 0x20B else 96)
        # 导入表数据目录可能超出已读头部，需要读更多
        with open(path, "rb") as f:
            data = f.read()
        imp_rva, imp_size = struct.unpack_from("<II", data, base_dir + 8)
        return {
            "ep": ep, "machine": machine,
            "import": (imp_rva, imp_size),
            "magic": magic,
        }
    except Exception:
        return None


# 只扫部分子目录（控制耗时）
SCAN_DIRS = [
    os.path.join(ROOT, "MSBuild", "Current", "Bin"),
    os.path.join(ROOT, "Common7", "IDE"),
    os.path.join(ROOT, "Common7", "Tools"),
    os.path.join(ROOT, "VC", "Tools", "MSVC"),
]

weird = []
for sd in SCAN_DIRS:
    for root, dirs, files in os.walk(sd):
        for name in files:
            if not name.lower().endswith(".exe"):
                continue
            p = os.path.join(root, name)
            info = pe_info(p)
            if info and info["ep"] == 0:
                weird.append((p, info))

print(f"EP=0 的 exe 数量: {len(weird)}")
for p, info in weird[:40]:
    print(f"  {p} machine=0x{info['machine']:X} "
          f"import_rva=0x{info['import'][0]:X}")
