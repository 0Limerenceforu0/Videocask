# -*- coding: utf-8 -*-
"""解析 PE 导入表，对比崩溃与正常 exe 的差异。"""

import struct

FILES = {
    "MSBuild.exe(崩)": r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\MSBuild.exe",
    "MSBuildTaskHost.exe(崩)": r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\MSBuildTaskHost.exe",
    "Tracker.exe(正常)": r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\Tracker.exe",
    "MSBuild.exe x86(正常)": r"D:\VS Studio\Community\MSBuild\Current\Bin\MSBuild.exe",
}


def imports(path):
    with open(path, "rb") as f:
        data = f.read()
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    opt_off = e_lfanew + 24
    magic = struct.unpack_from("<H", data, opt_off)[0]
    if magic == 0x20B:
        imp_rva, imp_size = struct.unpack_from("<II", data, opt_off + 120)
    else:
        imp_rva, imp_size = struct.unpack_from("<II", data, opt_off + 104)
    if not imp_rva:
        return []
    nsec = struct.unpack_from("<H", data, e_lfanew + 6)[0]
    opt_size = struct.unpack_from("<H", data, e_lfanew + 20)[0]
    sec_off = opt_off + opt_size

    def rva2off(rva):
        for i in range(nsec):
            s = sec_off + 40 * i
            vsize, vaddr, rsize, roff = struct.unpack_from("<IIII", data, s + 8)
            if vaddr <= rva < vaddr + max(vsize, rsize):
                return roff + (rva - vaddr)
        return None

    result = []
    off = rva2off(imp_rva)
    while off:
        _, _, _, name_rva = struct.unpack_from("<IIII", data, off)
        first_thunk = struct.unpack_from("<I", data, off + 16)[0]
        if name_rva == 0 and first_thunk == 0:
            break
        if name_rva:
            noff = rva2off(name_rva)
            if noff:
                dll_name = data[noff:data.index(b"\0", noff)].decode(
                    "ascii", "replace"
                )
                result.append(dll_name)
        off += 20
    return result


for label, path in FILES.items():
    try:
        imps = imports(path)
        print(f"{label}: {imps}")
    except Exception as e:
        print(f"{label}: ERROR {e}")
