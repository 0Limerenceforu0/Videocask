# -*- coding: utf-8 -*-
"""检查 exe 入口点代码与 CLR 头、调试目录。"""

import struct

FILES = {
    "MSBuild.exe amd64(崩)": r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\MSBuild.exe",
    "MSBuild.exe x86(正常)": r"D:\VS Studio\Community\MSBuild\Current\Bin\MSBuild.exe",
    "MSBuildTaskHost.exe(崩)": r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\MSBuildTaskHost.exe",
}


def dump(path):
    with open(path, "rb") as f:
        data = f.read()
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    nsec = struct.unpack_from("<H", data, e_lfanew + 6)[0]
    opt_size = struct.unpack_from("<H", data, e_lfanew + 20)[0]
    opt_off = e_lfanew + 24
    magic = struct.unpack_from("<H", data, opt_off)[0]
    ep_rva = struct.unpack_from("<I", data, opt_off + 16)[0]
    subsystem = struct.unpack_from("<H", data, opt_off + 68)[0]
    dll_chars = struct.unpack_from("<H", data, opt_off + 70)[0]
    base_dir = opt_off + (112 if magic == 0x20B else 96)
    clr_rva, clr_size = struct.unpack_from("<II", data, base_dir + 8 * 14)

    print(f"\n=== {path.split(chr(92))[-1]} [{path.split(chr(92))[-2]}]")
    print(f"entrypoint rva=0x{ep_rva:X} subsystem={subsystem} "
          f"dllchars=0x{dll_chars:X}")
    print("optional header 前 64 字节:",
          data[opt_off:opt_off + 64].hex(" "))

    def rva2off(rva):
        for i in range(nsec):
            s = opt_off + opt_size + 40 * i
            vsize, vaddr, rsize, roff = struct.unpack_from("<IIII", data, s + 8)
            if vaddr <= rva < vaddr + max(vsize, rsize):
                return roff + (rva - vaddr)
        return None

    ep_off = rva2off(ep_rva)
    if ep_off:
        print("entrypoint bytes:", data[ep_off:ep_off + 32].hex(" "))

    # CLR 头: cb, MajorRuntimeVersion, MinorRuntimeVersion, MetaData(rva,size),
    # Flags, EntryPointToken/nop, Resources, StrongName, CodeManager,
    # VTableFixups, ExportAddressTableJumps, ManagedNativeHeader
    clr_off = rva2off(clr_rva)
    if clr_off:
        cb, maj, minr, md_rva, md_size = struct.unpack_from(
            "<IHHII", data, clr_off
        )
        flags, ep_token = struct.unpack_from("<II", data, clr_off + 16)
        print(f"CLR: runtime={maj}.{minr} flags=0x{flags:X} "
              f"EntryPointToken=0x{ep_token:X}")
        md_off = rva2off(md_rva)
        if md_off:
            sig = struct.unpack_from("<I", data, md_off)[0]
            ver_len = struct.unpack_from("<I", data, md_off + 12)[0]
            ver = data[md_off + 16:md_off + 16 + ver_len].split(b"\0")[0]
            print(f"  metadata rva=0x{md_rva:X} size=0x{md_size:X} "
                  f"sig=0x{sig:X} version={ver.decode('utf-8', 'replace')}")

    # 调试目录: 取 CodeView PDB 路径
    dbg_rva, dbg_size = struct.unpack_from("<II", data, base_dir + 8 * 6)
    dbg_off = rva2off(dbg_rva)
    if dbg_off:
        n = dbg_size // 28
        for i in range(n):
            off = dbg_off + 28 * i
            _, _, _, type_cv, size_cv, addr, ptr = struct.unpack_from(
                "<IIIIII", data, off
            )
            if type_cv == 2:  # CODEVIEW
                cv = data[ptr:ptr + size_cv]
                if cv[:4] == b"RSDS":
                    pdb = cv[24:].split(b"\0")[0].decode("utf-8", "replace")
                    print(f"  PDB: {pdb}")


for p in FILES.values():
    dump(p)
