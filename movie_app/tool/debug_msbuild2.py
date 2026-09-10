# -*- coding: utf-8 -*-
"""调试 64 位 MSBuild，从进程内存读取崩溃 DLL 的 PE 导出表名称。"""

import ctypes
import ctypes.wintypes as wt
import os
import sys

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

DEBUG_PROCESS = 0x00000001
INFINITE = 0xFFFFFFFF
DBG_CONTINUE = 0x00010002
DBG_EXCEPTION_NOT_HANDLED = 0x80010001

EXCEPTION_DEBUG_EVENT = 1
CREATE_PROCESS_DEBUG_EVENT = 3
EXIT_PROCESS_DEBUG_EVENT = 5
LOAD_DLL_DEBUG_EVENT = 6
EXCEPTION_ACCESS_VIOLATION = 0xC0000005
EXCEPTION_BREAKPOINT = 0x80000003
EXCEPTION_SINGLE_STEP = 0x80000004

MSBUILD = r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\MSBuild.exe"


class STARTUPINFOW(ctypes.Structure):
    _fields_ = [("cb", wt.DWORD)] + [
        (n, wt.LPWSTR) for n in ("lpReserved", "lpDesktop", "lpTitle")
    ] + [
        (n, wt.DWORD)
        for n in (
            "dwX", "dwY", "dwXSize", "dwYSize", "dwXCountChars",
            "dwYCountChars", "dwFillAttribute", "dwFlags",
        )
    ] + [
        ("wShowWindow", wt.WORD),
        ("cbReserved2", wt.WORD),
        ("lpReserved2", ctypes.c_void_p),
        ("hStdInput", wt.HANDLE),
        ("hStdOutput", wt.HANDLE),
        ("hStdError", wt.HANDLE),
    ]


class PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("hProcess", wt.HANDLE),
        ("hThread", wt.HANDLE),
        ("dwProcessId", wt.DWORD),
        ("dwThreadId", wt.DWORD),
    ]


class DEBUG_EVENT(ctypes.Structure):
    _fields_ = [
        ("dwDebugEventCode", wt.DWORD),
        ("dwProcessId", wt.DWORD),
        ("dwThreadId", wt.DWORD),
        ("_pad", wt.DWORD),
        ("u", ctypes.c_ubyte * 512),
    ]


def rpm(hproc, addr, size):
    """ReadProcessMemory，返回 bytes 或 None。"""
    buf = ctypes.create_string_buffer(size)
    nread = ctypes.c_size_t(0)
    ok = kernel32.ReadProcessMemory(
        hproc, ctypes.c_void_p(addr), buf, size, ctypes.byref(nread)
    )
    if not ok:
        return None
    return buf.raw[: nread.value]


def pe_export_name(hproc, base):
    """从进程内存中的 PE 镜像读取导出表中的模块名。"""
    hdr = rpm(hproc, base, 0x1000)
    if not hdr or hdr[:2] != b"MZ":
        return None
    e_lfanew = int.from_bytes(hdr[0x3C:0x40], "little")
    pe_sig = hdr[e_lfanew:e_lfanew + 4]
    if pe_sig != b"PE\0\0":
        return None
    opt_off = e_lfanew + 24
    magic = int.from_bytes(hdr[opt_off:opt_off + 2], "little")
    if magic == 0x20B:  # PE32+
        export_rva = int.from_bytes(
            hdr[opt_off + 112:opt_off + 116], "little"
        )
        export_size = int.from_bytes(
            hdr[opt_off + 116:opt_off + 120], "little"
        )
    else:  # PE32
        export_rva = int.from_bytes(hdr[opt_off + 96:opt_off + 100], "little")
        export_size = int.from_bytes(hdr[opt_off + 100:opt_off + 104], "little")
    if not export_rva:
        return None
    # RVA -> 文件偏移（简单做法：读节表转换）
    nsec = int.from_bytes(hdr[e_lfanew + 6:e_lfanew + 8], "little")
    opt_size = int.from_bytes(hdr[e_lfanew + 20:e_lfanew + 22], "little")
    sec_off = opt_off + opt_size
    file_off = None
    for i in range(nsec):
        s = hdr[sec_off + 40 * i:sec_off + 40 * (i + 1)]
        vsize = int.from_bytes(s[8:12], "little")
        vaddr = int.from_bytes(s[12:16], "little")
        rsize = int.from_bytes(s[16:20], "little")
        roff = int.from_bytes(s[20:24], "little")
        if vaddr <= export_rva < vaddr + max(vsize, rsize):
            file_off = roff + (export_rva - vaddr)
            break
    if file_off is None:
        return None
    # 导出表在内存中按 RVA 排布，直接用 export_rva 从内存读
    exp = rpm(hproc, base + export_rva, min(export_size or 40, 40))
    if not exp:
        return None
    name_rva = int.from_bytes(exp[12:16], "little")
    if not name_rva:
        return None
    name_bytes = rpm(hproc, base + name_rva, 260)
    if not name_bytes:
        return None
    return name_bytes.split(b"\0")[0].decode("utf-8", "replace")


def main():
    si = STARTUPINFOW()
    si.cb = ctypes.sizeof(STARTUPINFOW)
    pi = PROCESS_INFORMATION()
    ok = kernel32.CreateProcessW(
        None, f'"{MSBUILD}" -version -nologo', None, None, False,
        DEBUG_PROCESS, None, os.path.dirname(MSBUILD),
        ctypes.byref(si), ctypes.byref(pi),
    )
    if not ok:
        print("CreateProcess failed:", ctypes.get_last_error())
        return
    hproc = pi.hProcess
    kernel32.CloseHandle(pi.hThread)

    ev = DEBUG_EVENT()
    dlls = []
    while True:
        if not kernel32.WaitForDebugEvent(ctypes.byref(ev), INFINITE):
            break
        code = ev.dwDebugEventCode
        pid, tid = ev.dwProcessId, ev.dwThreadId
        u = bytes(ev.u)
        status = DBG_CONTINUE

        if code == CREATE_PROCESS_DEBUG_EVENT:
            hproc = int.from_bytes(u[8:16], "little") or hproc
            dlls.append((int.from_bytes(u[24:32], "little"), "<exe>"))
        elif code == LOAD_DLL_DEBUG_EVENT:
            dlls.append((int.from_bytes(u[8:16], "little"), None))
        elif code == EXCEPTION_DEBUG_EVENT:
            exc_code = int.from_bytes(u[0:4], "little")
            exc_addr = int.from_bytes(u[16:24], "little")
            if exc_code not in (EXCEPTION_BREAKPOINT, EXCEPTION_SINGLE_STEP):
                print(f"EXCEPTION {hex(exc_code)} addr=0x{exc_addr:X}", flush=True)
                for base, name in dlls:
                    if base and base <= exc_addr < base + 0x10000000:
                        pname = pe_export_name(hproc, base)
                        print(f"  crash module base=0x{base:X}", flush=True)
                        print(f"  PE export name: {pname}", flush=True)
                status = DBG_EXCEPTION_NOT_HANDLED
        elif code == EXIT_PROCESS_DEBUG_EVENT:
            print(f"EXIT code=0x{int.from_bytes(u[0:4], 'little'):X}", flush=True)
            kernel32.ContinueDebugEvent(pid, tid, DBG_CONTINUE)
            break
        kernel32.ContinueDebugEvent(pid, tid, status)

    kernel32.CloseHandle(hproc)


if __name__ == "__main__":
    main()
