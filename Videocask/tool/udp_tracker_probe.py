#!/usr/bin/env python3
"""UDP tracker 连通性探针。

用途：判断本机到公开 tracker / DHT 节点的 UDP 通路是否可用。
BitTorrent 的 peer 发现严重依赖 UDP（tracker announce + DHT），
若 UDP 出海被拦，就只剩 TCP tracker，peer 池会小一个数量级。

协议：发送 UDP tracker connect 握手（protocol_id=0x41727101980, action=0），
正常应返回 16 字节、action=0 的 connect 响应。
DHT 节点不响应此握手，仅做可达性观察（超时即视为不可达）。
"""
import socket
import struct
import sys

PROTOCOL_ID = 0x41727101980
ACTION_CONNECT = 0

# (名称, 主机, 端口, 类型)
TARGETS = [
    ("opentrackr(UDP tracker)", "tracker.opentrackr.org", 1337, "tracker"),
    ("openbittorrent(UDP)", "tracker.openbittorrent.com", 6969, "tracker"),
    ("dler(UDP)", "tracker.dler.org", 6969, "tracker"),
    ("exodus.desync(UDP)", "exodus.desync.com", 6969, "tracker"),
    ("torrent.eu.org(UDP)", "tracker.torrent.eu.org", 451, "tracker"),
    ("dht.libtorrent.org", "dht.libtorrent.org", 25401, "dht"),
    ("dht.transmissionbt.com", "dht.transmissionbt.com", 6881, "dht"),
    ("router.bittorrent.com", "router.bittorrent.com", 6881, "dht"),
]

TIMEOUT = 4.0


def probe_tracker(host: str, port: int):
    """发 UDP tracker connect 握手，返回 (状态, 说明)。"""
    try:
        infos = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_DGRAM)
    except socket.gaierror as e:
        return "DNS失败", str(e)
    if not infos:
        return "DNS失败", "无 A 记录"

    addr = infos[0][4]
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(TIMEOUT)
    try:
        txid = 0x12345678
        req = struct.pack("!QII", PROTOCOL_ID, ACTION_CONNECT, txid)
        sock.sendto(req, addr)
        data, _ = sock.recvfrom(2048)
        if len(data) >= 16:
            action, tid = struct.unpack("!II", data[:8])
            if action == ACTION_CONNECT and tid == txid:
                return "可达", f"connect 响应正常 ({len(data)}B)"
            if action == 3:
                # action=3 是 error，说明通路是通的，只是握手被拒
                return "可达", "收到 error 响应（通路正常）"
            return "异常", f"action={action}"
        return "异常", f"响应过短 {len(data)}B"
    except socket.timeout:
        return "超时", f"{TIMEOUT}s 内无响应（UDP 可能被拦）"
    except OSError as e:
        return "错误", str(e)
    finally:
        sock.close()


def main():
    print("=" * 68)
    print("UDP 连通性探针：tracker announce / DHT 节点")
    print("=" * 68)
    print(f"{'目标':<30}{'主机:端口':<34}{'结果':<6}说明")
    print("-" * 68)
    ok = 0
    for name, host, port, kind in TARGETS:
        status, detail = probe_tracker(host, port)
        flag = "OK" if status == "可达" else "--"
        if status == "可达":
            ok += 1
        print(f"{name:<30}{host + ':' + str(port):<34}{flag:<6}{detail}")
    print("-" * 68)
    print(f"可达 {ok}/{len(TARGETS)}")
    if ok == 0:
        print()
        print("结论：UDP 通路基本不通。peer 发现只能靠 TCP tracker（数量很少），")
        print("      DHT 完全失效 —— 这会导致「节点只有 1 个、速度 10B/s」。")
    elif ok < len(TARGETS) // 2:
        print()
        print("结论：UDP 通路部分受限，peer 发现能力被显著削弱。")
    else:
        print()
        print("结论：UDP 通路大体正常，慢的原因更可能是资源本身做种少。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
