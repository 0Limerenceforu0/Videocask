"""诊断 Windows 命名管道"只读打开"是否被内核驱动拦截。

背景：Dart VM 在 Windows 上用命名管道实现子进程 stdio，其中 stdin 管道是
「server 端 PIPE_ACCESS_OUTBOUND + client 端 GENERIC_READ」的组合。
某些第三方内核驱动（实测：鲁大师 LudashiProtect64.sys）会让这种
**纯只读** 的 CreateFile 一律返回 ERROR_PIPE_BUSY(231)，而 GENERIC_WRITE /
GENERIC_READ|GENERIC_WRITE 不受影响。node(libuv)、python 用后两种，所以正常；
Dart 是唯一中招的常见运行时 —— 表现为所有 flutter/dart 命令都报：

    CreateFile failed 231 (所有的管道范例都在使用中。)
      at ../../runtime/bin/process_win.cc:717

后果：flutter analyze / test / pub get / build 全部无法启动子进程。
（不影响 bash / node / python 自己起进程，也不影响 dart 单进程命令如
dart format、dart --version。）

用法：python tool/pipe_readonly_diag.py
"""

import ctypes
from ctypes import wintypes
import uuid

k32 = ctypes.WinDLL("kernel32", use_last_error=True)

INBOUND, OUTBOUND, DUPLEX = 0x1, 0x2, 0x3
OVERLAPPED = 0x40000000
GENERIC_READ, GENERIC_WRITE = 0x80000000, 0x40000000
OPEN_EXISTING = 3
READ_ATTR, WRITE_ATTR = 0x80, 0x100
INVALID = ctypes.c_void_p(-1).value

k32.CreateNamedPipeW.restype = wintypes.HANDLE
k32.CreateNamedPipeW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                 wintypes.DWORD, wintypes.DWORD, wintypes.DWORD,
                                 wintypes.DWORD, ctypes.c_void_p]
k32.CreateFileW.restype = wintypes.HANDLE
k32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                            ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]


def probe(tag, smode, caccess, cflags):
    name = "\\\\.\\Pipe\\diag_%s" % uuid.uuid4().hex[:12]
    srv = k32.CreateNamedPipeW(name, smode | OVERLAPPED, 0, 1, 1024, 1024, 0, None)
    if srv == INVALID:
        print("%-34s 服务端创建失败 %d" % (tag, ctypes.get_last_error()))
        return None
    cli = k32.CreateFileW(name, caccess, 0, None, OPEN_EXISTING, cflags, None)
    err = ctypes.get_last_error()
    ok = cli != INVALID
    if ok:
        k32.CloseHandle(wintypes.HANDLE(cli))
    k32.CloseHandle(wintypes.HANDLE(srv))
    print("%-34s %s" % (tag, "正常" if ok else "失败 err=%d" % err))
    return ok


def driver_state():
    """查一下 LudashiProtect 内核驱动当前是否加载（只读查询，无需管理员）。"""
    import subprocess
    try:
        r = subprocess.run(["sc.exe", "query", "LudashiProtect"],
                           capture_output=True, text=True, timeout=10)
        text = (r.stdout or "") + (r.stderr or "")
    except Exception as e:  # noqa: BLE001
        print("  （驱动状态查询失败：%s）" % e)
        return None
    if "1058" in text or "1060" in text:
        print("  驱动服务：不存在（已被移除）")
        return False
    running = "RUNNING" in text.upper()
    print("  驱动服务：%s" % ("仍在运行（已加载进内存）" if running else "未运行"))
    if running:
        try:
            r2 = subprocess.run(
                ["powershell", "-NoProfile", "-Command",
                 "$d = Get-CimInstance Win32_SystemDriver -Filter \"Name='LudashiProtect'\" "
                 "-ErrorAction SilentlyContinue; if ($d) { Write-Output ($d.State + '|' + $d.PathName) }"],
                capture_output=True, text=True, timeout=20)
            line = (r2.stdout or "").strip()
            if line:
                print("  驱动详情：%s" % line)
        except Exception:  # noqa: BLE001
            pass
    return running


def main():
    print("命名管道只读打开检测\n")
    a = probe("client GENERIC_READ (Dart stdin)", OUTBOUND, GENERIC_READ,
              READ_ATTR | OVERLAPPED)
    b = probe("client GENERIC_WRITE (Dart stdout)", INBOUND, GENERIC_WRITE,
              WRITE_ATTR | OVERLAPPED)
    c = probe("client READ|WRITE (libuv/node)", DUPLEX,
              GENERIC_READ | GENERIC_WRITE, READ_ATTR | OVERLAPPED)
    print()
    if a is False and b and c:
        print("结论：只读打开被拦截 —— Dart 无法创建子进程 stdio。")
        print("  → flutter test / analyze / build、dart test 全部不可用。")
        print("\n驱动状态：")
        driver_state()
        print("\n处理（按优先级）：")
        print("  1) 【最可靠】重启 Windows。")
        print("     驱动文件在 C:\\Program Files (x86)\\LuDaShi\\LudashiProtect64.sys")
        print("     （**不在** C:\\Windows\\System32\\drivers，别去那儿找）。")
        print("     内核驱动一旦加载就无法在运行中卸载，Stop-Service 对 KernelDriver")
        print("     类型是无效操作（服务状态会一直是 Running）。")
        print("     只要 StartType 已是 Disabled（tool/fix_dart_pipes.bat 会设），")
        print("     重启后它就不会再加载 → 拦截消失。")
        print("  2) 或彻底卸载鲁大师（含 C:\\Program Files (x86)\\LuDaShi 目录）。")
        print("  3) 不想重启时可试管理员执行 `sc stop LudashiProtect`，")
        print("     但多数内核驱动不支持动态停止，成功率低。")
        print("\n验证：修好后重跑本脚本，第一行应显示「正常」。")
    elif a:
        print("结论：未被拦截，Dart 子进程 stdio 正常。")
    else:
        print("结论：异常，只读与只写均受影响。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
