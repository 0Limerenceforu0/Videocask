# -*- coding: utf-8 -*-
"""完整对比 PE 头信息：数据目录、节表、CLR 头。"""

import struct

FILES = {
    "MSBuild.exe amd64(崩)": r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\MSBuild.exe",
    "MSBuild.exe x86(正常)": r"D:\VS Studio\Community\MSBuild\Current\Bin\MSBuild.exe",
}

DIR_NAMES = [
    "Export", "Import", "Resource", "Exception", "Security", "Relocation",
    "Debug", "Architecture", "GlobalPtr", "TLS", "LoadConfig", "BoundImport",
    "IAT", "DelayImport", "CLR", "Reserved",
]


def dump(path):
    with open(path, "rb") as f:
        data = f.read()
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    machine = struct.unpack_from("<H", data, e_lfanew + 4)[0]
    nsec = struct.unpack_from("<H", data, e_lfanew + 6)[0]
    opt_size = struct.unpack_from("<H", data, e_lfanew + 20)[0]
    opt_off = e_lfanew + 24
    magic = struct.unpack_from("<H", data, opt_off)[0]
    chars = struct.unpack_from("<H", data, e_lfanew + 22)[0]
    print(f"\n=== {path}")
    print(f"machine=0x{machine:X} magic=0x{magic:X} sections={nsec} "
          f"opt_size={opt_size} characteristics=0x{chars:X}")

    ndir = struct.unpack_from("<I", data, opt_off + 108)[0]
    print(f"NumberOfRvaAndSizes={ndir}")
    base_dir = opt_off + (112 if magic == 0x20B else 96)
    for i in range(min(ndir, 16)):
        rva, size = struct.unpack_from("<II", data, base_dir + 8 * i)
        if rva or size:
            print(f"  dir[{i:2}] {DIR_NAMES[i]:12} rva=0x{rva:08X} size=0x{size:X}")

    sec_off = opt_off + opt_size
    print("节表:")
    for i in range(nsec):
        s = sec_off + 40 * i
        name = data[s:s + 8].rstrip(b"\0").decode("ascii", "replace")
        vsize, vaddr, rsize, roff = struct.unpack_from("<IIII", data, s + 8)
        chars_s = struct.unpack_from("<I", data, s + 36)[0]
        print(f"  {name:8} vaddr=0x{vaddr:08X} vsize=0x{vsize:08X} "
              f"rawsize=0x{rsize:08X} rawoff=0x{roff:08X} chars=0x{chars_s:08X}")

    # TLS 目录详情
    tls_i = 9
    rva, size = struct.unpack_from("<II", data, base_dir + 8 * tls_i)
    if rva and magic == 0x20B:
        off = None
        for i in range(nsec):
            s = sec_off + 40 * i
            vsize, vaddr, rsize, roff = struct.unpack_from("<IIII", data, s + 8)
            if vaddr <= rva < vaddr + max(vsize, rsize):
                off = roff + (rva - vaddr)
                break
        if off is not None:
            fields = struct.unpack_from("<QQQII", data, off)
            print("TLS目录: Start=0x%X End=0x%X Index=0x%X Callbacks=0x%X "
                  "Zeros=0x%X" % fields)


for p in FILES.values():
    dump(p)
