# -*- coding: utf-8 -*-
"""用 Windows 调试 API 捕获 64 位 MSBuild 启动崩溃的异常地址与出错模块。"""

import ctypes
import ctypes.wintypes as wt
import os
import sys

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

DEBUG_PROCESS = 0x00000001
INFINITE = 0xFFFFFFFF
DBG_CONTINUE = 0x00010002
DBG_EXCEPTION_NOT_HANDLED = 0x80010001
TH32CS_SNAPMODULE = 0x00000008
TH32CS_SNAPMODULE32 = 0x00000010

EXCEPTION_DEBUG_EVENT = 1
CREATE_PROCESS_DEBUG_EVENT = 3
EXIT_PROCESS_DEBUG_EVENT = 5
LOAD_DLL_DEBUG_EVENT = 6

EXCEPTION_ACCESS_VIOLATION = 0xC0000005
EXCEPTION_BREAKPOINT = 0x80000003
EXCEPTION_SINGLE_STEP = 0x80000004

MSBUILD = sys.argv[1] if len(sys.argv) > 1 else (
    r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\MSBuild.exe"
)

STARTUPINFO = ctypes.c_buffer(120)  # STARTUPINFOW sizeof=104 x86 / 120? 用结构体更稳


class STARTUPINFOW(ctypes.Structure):
    _fields_ = [
        ("cb", wt.DWORD),
        ("lpReserved", wt.LPWSTR),
        ("lpDesktop", wt.LPWSTR),
        ("lpTitle", wt.LPWSTR),
        ("dwX", wt.DWORD),
        ("dwY", wt.DWORD),
        ("dwXSize", wt.DWORD),
        ("dwYSize", wt.DWORD),
        ("dwXCountChars", wt.DWORD),
        ("dwYCountChars", wt.DWORD),
        ("dwFillAttribute", wt.DWORD),
        ("dwFlags", wt.DWORD),
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


# DEBUG_EVENT: {DWORD code; DWORD pid; DWORD tid; union {...} u;}
# 64 位下 union 对齐为 8，因此 union 偏移为 16，其后 512 字节足够容纳最大成员。
class DEBUG_EVENT(ctypes.Structure):
    _fields_ = [
        ("dwDebugEventCode", wt.DWORD),
        ("dwProcessId", wt.DWORD),
        ("dwThreadId", wt.DWORD),
        ("_pad", wt.DWORD),
        ("u", ctypes.c_ubyte * 512),
    ]


class MODULEENTRY32W(ctypes.Structure):
    _fields_ = [
        ("dwSize", wt.DWORD),
        ("th32ModuleID", wt.DWORD),
        ("th32ProcessID", wt.DWORD),
        ("GlblcntUsage", wt.DWORD),
        ("ProccntUsage", wt.DWORD),
        ("modBaseAddr", ctypes.c_void_p),
        ("modBaseSize", wt.DWORD),
        ("hModule", wt.HMODULE),
        ("szModule", ctypes.c_wchar * 256),
        ("szExePath", ctypes.c_wchar * 260),
    ]


def list_modules(pid):
    snap = kernel32.CreateToolhelp32Snapshot(
        TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid
    )
    if snap == ctypes.c_void_p(-1).value or snap == -1:
        return []
    mods = []
    me = MODULEENTRY32W()
    me.dwSize = ctypes.sizeof(MODULEENTRY32W)
    if kernel32.Module32FirstW(snap, ctypes.byref(me)):
        while True:
            mods.append((int(me.modBaseAddr or 0), me.modBaseSize, me.szExePath))
            me2 = MODULEENTRY32W()
            me2.dwSize = ctypes.sizeof(MODULEENTRY32W)
            # 重新利用同一结构体
            me.dwSize = ctypes.sizeof(MODULEENTRY32W)
            if not kernel32.Module32NextW(snap, ctypes.byref(me)):
                break
    kernel32.CloseHandle(snap)
    return mods


def module_for_address(pid, addr):
    for base, size, path in list_modules(pid):
        if base <= addr < base + size:
            return path, addr - base
    return None, 0


def main():
    si = STARTUPINFOW()
    si.cb = ctypes.sizeof(STARTUPINFOW)
    pi = PROCESS_INFORMATION()
    cmdline = f'"{MSBUILD}" -version -nologo'

    ok = kernel32.CreateProcessW(
        None,
        cmdline,
        None,
        None,
        False,
        DEBUG_PROCESS,
        None,
        os.path.dirname(MSBUILD),
        ctypes.byref(si),
        ctypes.byref(pi),
    )
    if not ok:
        print("CreateProcess failed:", ctypes.get_last_error())
        return

    kernel32.CloseHandle(pi.hThread)
    kernel32.CloseHandle(pi.hProcess)

    ev = DEBUG_EVENT()
    seen_av = False
    dll_bases = []  # (base, name)
    hproc = None
    while True:
        if not kernel32.WaitForDebugEvent(ctypes.byref(ev), INFINITE):
            print("WaitForDebugEvent failed:", ctypes.get_last_error())
            break
        code = ev.dwDebugEventCode
        pid = ev.dwProcessId
        tid = ev.dwThreadId
        u = bytes(ev.u)
        status = DBG_CONTINUE

        if code == CREATE_PROCESS_DEBUG_EVENT:
            # CREATE_PROCESS_DEBUG_INFO: hFile(8) hProcess(8) hThread(8)
            # lpBaseOfImage(8) dwDebugInfoFileOffset(4) ...
            hproc = int.from_bytes(u[8:16], "little")
            base = int.from_bytes(u[24:32], "little")
            dll_bases.append((base, "<exe>"))
        elif code == LOAD_DLL_DEBUG_EVENT:
            base = int.from_bytes(u[8:16], "little")
            lp_image_name = int.from_bytes(u[24:32], "little")
            f_unicode = int.from_bytes(u[32:34], "little")
            name = None
            if lp_image_name and hproc:
                buf = ctypes.c_uint64(0)
                nread = ctypes.c_size_t(0)
                if kernel32.ReadProcessMemory(
                    hproc,
                    ctypes.c_void_p(lp_image_name),
                    ctypes.byref(buf),
                    8,
                    ctypes.byref(nread),
                ):
                    ptr = buf.value
                    if ptr:
                        sbuf = ctypes.create_unicode_buffer(1024) if f_unicode \
                            else ctypes.create_string_buffer(1024)
                        if kernel32.ReadProcessMemory(
                            hproc,
                            ctypes.c_void_p(ptr),
                            sbuf,
                            ctypes.sizeof(sbuf),
                            ctypes.byref(nread),
                        ):
                            name = sbuf.value if f_unicode \
                                else sbuf.value.decode("mbcs", "replace")
            dll_bases.append((base, name or "?"))
        elif code == EXCEPTION_DEBUG_EVENT:
            exc_code = int.from_bytes(u[0:4], "little")
            exc_addr = int.from_bytes(u[16:24], "little", signed=False)
            first_chance = int.from_bytes(u[152:156], "little")
            if exc_code in (EXCEPTION_BREAKPOINT, EXCEPTION_SINGLE_STEP):
                status = DBG_CONTINUE
            else:
                name = {EXCEPTION_ACCESS_VIOLATION: "ACCESS_VIOLATION"}.get(
                    exc_code, hex(exc_code)
                )
                print(
                    f"EXCEPTION {name} addr=0x{exc_addr:X} "
                    f"first_chance={first_chance}",
                    flush=True,
                )
                if exc_code == EXCEPTION_ACCESS_VIOLATION and not seen_av:
                    seen_av = True
                    hit = None
                    for base, mname in dll_bases:
                        if base and base <= exc_addr < base + 0x2000000:
                            hit = (mname, exc_addr - base)
                    print(f"  -> fault in module: {hit}", flush=True)
                    rw = int.from_bytes(u[32:40], "little")
                    target = int.from_bytes(u[40:48], "little")
                    print(f"  -> access type={rw} target=0x{target:X}", flush=True)
                    print(f"  -> {len(dll_bases)} modules loaded so far:", flush=True)
                    for base, mname in dll_bases:
                        print(f"     0x{base:X}  {mname}", flush=True)
                status = DBG_EXCEPTION_NOT_HANDLED
        elif code == EXIT_PROCESS_DEBUG_EVENT:
            exit_code = int.from_bytes(u[0:4], "little")
            print(f"EXIT_PROCESS code=0x{exit_code:X}", flush=True)
            kernel32.ContinueDebugEvent(pid, tid, DBG_CONTINUE)
            break

        kernel32.ContinueDebugEvent(pid, tid, status)


if __name__ == "__main__":
    main()
