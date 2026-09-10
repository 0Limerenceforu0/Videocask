# -*- coding: utf-8 -*-
"""捕获 MSBuild 崩溃时的寄存器与指令字节，精确定位空指针来源。"""

import ctypes
import ctypes.wintypes as wt
import os

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

DEBUG_PROCESS = 0x1
INFINITE = 0xFFFFFFFF
DBG_CONTINUE = 0x00010002
DBG_EXCEPTION_NOT_HANDLED = 0x80010001
EXCEPTION_DEBUG_EVENT = 1
CREATE_PROCESS_DEBUG_EVENT = 3
EXIT_PROCESS_DEBUG_EVENT = 5
EXCEPTION_ACCESS_VIOLATION = 0xC0000005
EXCEPTION_BREAKPOINT = 0x80000003
EXCEPTION_SINGLE_STEP = 0x80000004
CONTEXT_AMD64 = 0x100000
CONTEXT_CONTROL = 0x100001
CONTEXT_INTEGER = 0x100002
CONTEXT_FULL_AMD64 = CONTEXT_AMD64 | CONTEXT_CONTROL | CONTEXT_INTEGER | 0x4 | 0x8

MSBUILD = r"D:\VS Studio\Community\MSBuild\Current\Bin\amd64\MSBuild.exe"


class STARTUPINFOW(ctypes.Structure):
    _fields_ = [("cb", wt.DWORD)] + [
        (n, wt.LPWSTR) for n in ("lpReserved", "lpDesktop", "lpTitle")
    ] + [
        (n, wt.DWORD)
        for n in ("dwX", "dwY", "dwXSize", "dwYSize", "dwXCountChars",
                  "dwYCountChars", "dwFillAttribute", "dwFlags")
    ] + [
        ("wShowWindow", wt.WORD), ("cbReserved2", wt.WORD),
        ("lpReserved2", ctypes.c_void_p),
        ("hStdInput", wt.HANDLE), ("hStdOutput", wt.HANDLE),
        ("hStdError", wt.HANDLE),
    ]


class PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [("hProcess", wt.HANDLE), ("hThread", wt.HANDLE),
                ("dwProcessId", wt.DWORD), ("dwThreadId", wt.DWORD)]


class DEBUG_EVENT(ctypes.Structure):
    _fields_ = [("dwDebugEventCode", wt.DWORD), ("dwProcessId", wt.DWORD),
                ("dwThreadId", wt.DWORD), ("_pad", wt.DWORD),
                ("u", ctypes.c_ubyte * 512)]


class CONTEXT(ctypes.Structure):
    _fields_ = [
        ("P1Home", ctypes.c_uint64), ("P2Home", ctypes.c_uint64),
        ("P3Home", ctypes.c_uint64), ("P4Home", ctypes.c_uint64),
        ("P5Home", ctypes.c_uint64), ("P6Home", ctypes.c_uint64),
        ("ContextFlags", wt.DWORD), ("MxCsr", wt.DWORD),
        ("SegCs", wt.WORD), ("SegDs", wt.WORD), ("SegEs", wt.WORD),
        ("SegFs", wt.WORD), ("SegGs", wt.WORD), ("SegSs", wt.WORD),
        ("EFlags", wt.DWORD),
        ("Dr0", ctypes.c_uint64), ("Dr1", ctypes.c_uint64),
        ("Dr2", ctypes.c_uint64), ("Dr3", ctypes.c_uint64),
        ("Dr6", ctypes.c_uint64), ("Dr7", ctypes.c_uint64),
        ("Rax", ctypes.c_uint64), ("Rcx", ctypes.c_uint64),
        ("Rdx", ctypes.c_uint64), ("Rbx", ctypes.c_uint64),
        ("Rsp", ctypes.c_uint64), ("Rbp", ctypes.c_uint64),
        ("Rsi", ctypes.c_uint64), ("Rdi", ctypes.c_uint64),
        ("R8", ctypes.c_uint64), ("R9", ctypes.c_uint64),
        ("R10", ctypes.c_uint64), ("R11", ctypes.c_uint64),
        ("R12", ctypes.c_uint64), ("R13", ctypes.c_uint64),
        ("R14", ctypes.c_uint64), ("R15", ctypes.c_uint64),
        ("Rip", ctypes.c_uint64),
        ("FltSave", ctypes.c_ubyte * 512),
    ]


def rpm(hproc, addr, size):
    buf = ctypes.create_string_buffer(size)
    nread = ctypes.c_size_t(0)
    if not kernel32.ReadProcessMemory(
        hproc, ctypes.c_void_p(addr), buf, size, ctypes.byref(nread)
    ):
        return None
    return buf.raw[: nread.value]


def main():
    si = STARTUPINFOW()
    si.cb = ctypes.sizeof(STARTUPINFOW)
    pi = PROCESS_INFORMATION()
    if not kernel32.CreateProcessW(
        None, f'"{MSBUILD}" -version -nologo', None, None, False,
        DEBUG_PROCESS, None, os.path.dirname(MSBUILD),
        ctypes.byref(si), ctypes.byref(pi),
    ):
        print("CreateProcess failed")
        return
    hproc, hthread = pi.hProcess, pi.hThread

    ev = DEBUG_EVENT()
    done = False
    while not done:
        if not kernel32.WaitForDebugEvent(ctypes.byref(ev), INFINITE):
            break
        code = ev.dwDebugEventCode
        pid, tid = ev.dwProcessId, ev.dwThreadId
        u = bytes(ev.u)
        status = DBG_CONTINUE
        if code == EXCEPTION_DEBUG_EVENT:
            exc_code = int.from_bytes(u[0:4], "little")
            exc_addr = int.from_bytes(u[16:24], "little")
            if exc_code not in (EXCEPTION_BREAKPOINT, EXCEPTION_SINGLE_STEP):
                print(f"EXCEPTION {hex(exc_code)} ip=0x{exc_addr:X}")
                code_bytes = rpm(hproc, exc_addr - 16, 48)
                if code_bytes:
                    print("  指令字节(前16后32):")
                    print("   " + code_bytes[:16].hex(" "))
                    print("   " + code_bytes[16:].hex(" "))
                ctx = CONTEXT()
                ctx.ContextFlags = CONTEXT_FULL_AMD64
                hT = kernel32.OpenThread(0x1FFFFF, False, tid)  # THREAD_ALL_ACCESS
                if kernel32.GetThreadContext(
                    ctypes.c_void_p(hT or hthread), ctypes.byref(ctx)
                ):
                    regs = ["Rax", "Rcx", "Rdx", "Rbx", "Rsp", "Rbp",
                            "Rsi", "Rdi", "R8", "R9", "R10", "R11",
                            "R12", "R13", "R14", "R15", "Rip"]
                    for r in regs:
                        print(f"  {r}=0x{getattr(ctx, r):016X}")
                status = DBG_EXCEPTION_NOT_HANDLED
        elif code == EXIT_PROCESS_DEBUG_EVENT:
            print(f"EXIT code=0x{int.from_bytes(u[0:4], 'little'):X}")
            kernel32.ContinueDebugEvent(pid, tid, DBG_CONTINUE)
            done = True
            continue
        kernel32.ContinueDebugEvent(pid, tid, status)

    kernel32.CloseHandle(hthread)
    kernel32.CloseHandle(hproc)


if __name__ == "__main__":
    main()
