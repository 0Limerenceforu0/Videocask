#!/usr/bin/env python3
"""公开 tracker 实测工具（真实 announce，不是「能否 ping 通」）。

为什么要这个脚本：
    曾经按「443 端口不易被封」的直觉给列表加了 9 个 https:// tracker，
    结果逐条实测 **8 条根本不存在 / 1 条 403**，等于一条都没生效，还让
    「磁力播不出来」的问题原地踏步。判断 tracker 唯一可信的方法是：
    带真实 infohash 发 announce，看有没有回 bencoded 的 peers。

用法：
    python tool/tracker_probe.py                 # 默认用内置清单
    python tool/tracker_probe.py <infohash40>    # 指定 40 位 infohash

输出每行：URL + 结果（peers 数量 / failure reason / 网络错误）。
只有 `OK peers≈N`（N>0）才算「这条 tracker 在当前网络真的能发现 peer」。
"""

from __future__ import annotations

import ssl
import sys
import urllib.parse
import urllib.request

# 默认 infohash：Ubuntu 22.04 LTS（长期有做种，适合当探针）
DEFAULT_INFOHASH = "2C6B6858D61DA9543D4231A71DB4B1C9264B0685"

# 待测清单：改成你关心的域名即可
CANDIDATES = [
    # ---- HTTP(TCP)：实测可用 ----
    "http://tracker.opentrackr.org:1337/announce",
    "http://tracker.qu.ax:6969/announce",
    "http://tracker.dler.org:6969/announce",
    "http://tracker2.itzmx.com:6961/announce",
    "http://tracker1.itzmx.com:8080/announce",
    "http://open.tracker.cl:1337/announce",
    "http://nyaa.tracker.wf:7777/announce",
    "http://sukebei.tracker.wf:8888/announce",
    "http://t.nyaatracker.com/announce",
    # ---- UDP：需另用 UDP 探针，此处仅列出不测 ----
    # "udp://tracker.opentrackr.org:1337/announce",
]


def build_query(infohash: bytes) -> str:
    return urllib.parse.urlencode(
        {
            "info_hash": infohash.decode("latin-1"),
            "peer_id": "-qB4600-123456789012",
            "port": 6881,
            "uploaded": 0,
            "downloaded": 0,
            "left": 1000,
            "compact": 1,
            "event": "started",
        },
        encoding="latin-1",
    )


def count_peers(body: bytes) -> int:
    """极简解析：只关心 peers 字段（compact 时每 6 字节一个 peer）。"""
    i = body.find(b"5:peers")
    if i < 0:
        return -1
    j = i + 7
    if body[j : j + 1] == b"l":
        return body.count(b"7:peer id")
    colon = body.find(b":", j)
    if colon < 0:
        return -1
    try:
        n = int(body[j:colon])
    except ValueError:
        return -1
    return n // 6 if n else 0


def probe(url: str, infohash: bytes, timeout: float = 8.0) -> str:
    try:
        full = url + ("&" if "?" in url else "?") + build_query(infohash)
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        req = urllib.request.Request(full, headers={"User-Agent": "qBittorrent/4.6.0"})
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            body = r.read()
        if body.startswith(b"d") and b"failure reason" in body:
            msg = body.split(b"14:failure reason")[-1][:60]
            return f"bencoded-FAIL {msg!r}"
        return f"OK peers≈{count_peers(body)} size={len(body)}"
    except Exception as e:  # noqa: BLE001 - 探测工具，异常就是结果
        return f"ERR {type(e).__name__}: {str(e)[:70]}"


def main() -> int:
    import os

    # 探测必须直连：系统代理会伪装成 502/403，导致误判 tracker 已死。
    for k in (
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "http_proxy",
        "https_proxy",
        "ALL_PROXY",
        "all_proxy",
    ):
        os.environ.pop(k, None)

    hex_hash = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_INFOHASH
    infohash = bytes.fromhex(hex_hash)
    print(f"infohash = {hex_hash}（{len(infohash)} 字节）")
    for url in CANDIDATES:
        print(f"{url:52s} {probe(url, infohash)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
