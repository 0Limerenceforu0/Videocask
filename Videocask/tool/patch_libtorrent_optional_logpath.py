# -*- coding: utf-8 -*-
"""让 libtorrent_flutter 把 `lt_set_log_path` 当作可选符号（Windows 磁力修复）。

## 背景（真实故障）

libtorrent_flutter 1.9.9 的 `TorrentBridgeBindings` 构造函数会**急切** lookup
全部 30 个 FFI 符号。其中 `lt_set_log_path` 只用于「把原生日志写进文件」，
是一个纯可选能力。但插件随包发布的 Windows 预编译 DLL
（`prebuilt/windows/x64/libtorrent_flutter.dll`，7.1 MB, 2025-11-07）是**陈旧
构建产物**，比 Dart 绑定落后一个提交，没有导出该符号。

结果：Windows 上只要调用 `LibtorrentFlutter.init()` 就抛

    Invalid argument(s): Failed to lookup symbol 'lt_set_log_path':
    The specified procedure could not be found.

→ `TorrentPlayerService._isInitialized` 永远为 false → UI 进入指数退避无限
重试（实测「正在自动重试第 190 次 · 启动 P2P 引擎」），磁力资源完全无法播放。
Android 不受影响：我们的 .so 是从源码重建的，含该符号。

## 补丁内容（纯 Dart，不碰任何原生库）

1. `lib/src/ffi_bindings.dart`
   - `late final LtSetLogPath setLogPath;` → 可空类型
   - 构造函数的急切 lookup → `_tryLookupSetLogPath(_lib)`（找不到返回 null）
   - 文件末尾追加 `_tryLookupSetLogPath()` 辅助函数
2. `lib/src/libtorrent_flutter_base.dart`
   - `_b.setLogPath(ptr)` → `_b.setLogPath?.call(ptr)`

Android 上符号存在，照常生效；Windows 上自动降级为 no-op，引擎正常初始化。

## 用法

    python tool/patch_libtorrent_optional_logpath.py            # 打补丁（幂等）
    python tool/patch_libtorrent_optional_logpath.py --check    # 只检查
    python tool/patch_libtorrent_optional_logpath.py --revert   # 还原

补丁目标是 pub 缓存里的包（以 `.dart_tool/package_config.json` 解析结果为准），
所以 `flutter pub cache repair` / 换机器后需要重新执行一次。
`flutter pub get` 本身不会覆盖它（包版本与内容哈希未变）。
"""

import argparse
import json
import os
import sys

MARKER = "[videocask-patch]"

PROJECT = os.environ.get(
    "VIDEOCASK_PROJECT",
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
)

FIELD_OLD = "  late final LtSetLogPath setLogPath;"
FIELD_NEW = "  late final LtSetLogPath? setLogPath;"

LOOKUP_OLD = """    setLogPath = _lib
        .lookup<NativeFunction<_SetLogPathN>>('lt_set_log_path')
        .asFunction<LtSetLogPath>();"""

LOOKUP_NEW = """    // [videocask-patch] `lt_set_log_path` is optional: the prebuilt Windows
    // DLL shipped with 1.9.9 predates the symbol. A missing *logging* symbol
    // must not abort the whole binding table / engine initialisation.
    setLogPath = _tryLookupSetLogPath(_lib);"""

HELPER = """
/// [videocask-patch] Optional lookup for the native log-path setter.
///
/// `lt_set_log_path` only routes native debug logging to a file. Some prebuilt
/// native libraries (notably the Windows DLL of 1.9.9) do not export it, and a
/// hard lookup there made `LibtorrentFlutter.init()` throw
/// `Failed to lookup symbol 'lt_set_log_path'`, leaving the P2P engine
/// permanently uninitialised on Windows.
LtSetLogPath? _tryLookupSetLogPath(DynamicLibrary lib) {
  try {
    return lib
        .lookup<NativeFunction<_SetLogPathN>>('lt_set_log_path')
        .asFunction<LtSetLogPath>();
  } catch (_) {
    return null;
  }
}
"""

CALL_OLD = "      _b.setLogPath(ptr);"
CALL_NEW = "      _b.setLogPath?.call(ptr); // [videocask-patch] optional symbol"


def package_dir():
    cfg_path = os.path.join(PROJECT, ".dart_tool", "package_config.json")
    if not os.path.isfile(cfg_path):
        sys.exit("找不到 %s，请先 flutter pub get。" % cfg_path)
    with open(cfg_path, "r", encoding="utf-8") as f:
        cfg = json.load(f)
    for pkg in cfg.get("packages", []):
        if pkg.get("name") != "libtorrent_flutter":
            continue
        uri = pkg.get("rootUri", "")
        if uri.startswith("file:///"):
            path = uri[len("file:///"):]
            # file:///F:/xxx -> F:/xxx
            if len(path) > 1 and path[1] == ":":
                return path.replace("/", os.sep)
        base = os.path.dirname(cfg_path)
        return os.path.normpath(os.path.join(base, uri.replace("file://", "")))
    sys.exit("package_config.json 里没有 libtorrent_flutter。")


def read(path):
    """统一按 LF 返回文本，并带回原始换行风格，避免 CRLF 源码匹配失败。"""
    with open(path, "r", encoding="utf-8", newline="") as f:
        raw = f.read()
    newline = "\r\n" if "\r\n" in raw else "\n"
    return raw.replace("\r\n", "\n"), newline


def write(path, text, newline):
    if newline == "\r\n":
        text = text.replace("\n", "\r\n")
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def status(bindings_text, base_text):
    patched_bindings = (FIELD_NEW in bindings_text) and (
        "_tryLookupSetLogPath" in bindings_text
    )
    patched_base = "setLogPath?.call" in base_text
    return patched_bindings, patched_base


def apply_patch():
    root = package_dir()
    bindings = os.path.join(root, "lib", "src", "ffi_bindings.dart")
    base = os.path.join(root, "lib", "src", "libtorrent_flutter_base.dart")
    for p in (bindings, base):
        if not os.path.isfile(p):
            sys.exit("补丁目标不存在：%s" % p)

    btext, bnl = read(bindings)
    stext, snl = read(base)
    done_b, done_s = status(btext, stext)
    print("插件目录: %s" % root)
    print("当前状态: bindings=%s base=%s" % ("已打" if done_b else "未打",
                                             "已打" if done_s else "未打"))

    changed = []

    if not done_b:
        if FIELD_OLD not in btext or LOOKUP_OLD not in btext:
            sys.exit(
                "ffi_bindings.dart 结构与预期不符（插件版本可能变了）。\n"
                "请人工核对后更新本脚本。"
            )
        btext = btext.replace(FIELD_OLD, FIELD_NEW, 1)
        btext = btext.replace(LOOKUP_OLD, LOOKUP_NEW, 1)
        if "_tryLookupSetLogPath(DynamicLibrary lib)" not in btext:
            btext = btext.rstrip("\n") + "\n" + HELPER
        write(bindings, btext, bnl)
        changed.append(bindings)

    if not done_s:
        if CALL_OLD not in stext:
            sys.exit("libtorrent_flutter_base.dart 结构不符合预期，已中止。")
        stext = stext.replace(CALL_OLD, CALL_NEW, 1)
        write(base, stext, snl)
        changed.append(base)

    if not changed:
        print("已是补丁状态，无需重复操作。")
        return 0
    for p in changed:
        print("已修改: %s" % p)
    print("完成。重新构建前建议 flutter clean 一次（仅 Windows runner 即可）。")
    return 0


def revert_patch():
    root = package_dir()
    bindings = os.path.join(root, "lib", "src", "ffi_bindings.dart")
    base = os.path.join(root, "lib", "src", "libtorrent_flutter_base.dart")

    btext, bnl = read(bindings)
    stext, snl = read(base)
    if FIELD_NEW in btext:
        btext = btext.replace(FIELD_NEW, FIELD_OLD, 1)
    if LOOKUP_NEW in btext:
        btext = btext.replace(LOOKUP_NEW, LOOKUP_OLD, 1)
    btext = btext.replace(HELPER, "", 1)
    write(bindings, btext, bnl)

    if "setLogPath?.call" in stext:
        stext = stext.replace(CALL_NEW, CALL_OLD, 1)
        write(base, stext, snl)
    print("已还原（如需彻底复原可 flutter pub cache repair）。")
    return 0


def check_only():
    root = package_dir()
    btext, _ = read(os.path.join(root, "lib", "src", "ffi_bindings.dart"))
    stext, _ = read(os.path.join(root, "lib", "src", "libtorrent_flutter_base.dart"))
    done_b, done_s = status(btext, stext)
    print("插件目录: %s" % root)
    print("bindings: %s" % ("已打补丁" if done_b else "未打补丁"))
    print("base    : %s" % ("已打补丁" if done_s else "未打补丁"))
    return 0 if (done_b and done_s) else 1


def main():
    ap = argparse.ArgumentParser(description="libtorrent_flutter 可选符号补丁")
    ap.add_argument("--check", action="store_true", help="只检查状态")
    ap.add_argument("--revert", action="store_true", help="还原补丁")
    args = ap.parse_args()
    if args.check:
        return check_only()
    if args.revert:
        return revert_patch()
    return apply_patch()


if __name__ == "__main__":
    sys.exit(main())
