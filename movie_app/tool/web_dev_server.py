# -*- coding: utf-8 -*-
"""movie_app Web 端本地服务器：静态托管 + CORS 代理。

浏览器直连 CMS / 视频源会被同源策略拦截（这就是网页端「没有数据」的根因）。
本脚本用一个进程同时解决两件事：

  1. 静态托管 `build/web`（Flutter Web 产物）
  2. `/proxy?url=<url-encoded>` 转发任意 HTTP(S) 请求并附加 CORS 头，
     支持 Range（视频拖动）、重定向跟随、自定义 Referer/UA

用法:
  python tool/web_dev_server.py [--port 8787] [--root build/web]

启动后浏览器打开 http://127.0.0.1:8787/ 即可。
"""

import argparse
import json
import math
import os
import re
import socketserver
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

DEFAULT_UPSTREAM_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)

# 允许转发的目标协议（禁止 file:// 等本地协议，避免把本机文件暴露给网页）
ALLOWED_SCHEMES = ("http", "https")

# 单次转发最多读取的字节数，避免异常响应把内存打满
MAX_UPSTREAM_BYTES = 64 * 1024 * 1024

# 图片扩展名：源站直连失败时回退到公共图片代理
IMAGE_EXTS = (".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif", ".svg")

# 公共图片代理模板：由对方服务器拉取源图并附带 CORS 头，
# 用于绕开本地网络对部分图床（如 img.feifeiimg.vip）的 TLS 封锁。
IMAGE_FALLBACK_TEMPLATE = "https://wsrv.nl/?url={}"

# 图片代理超时（秒）
IMAGE_FALLBACK_TIMEOUT = 25


def rewrite_m3u8(base_url: str, text: str) -> str:
    """把 m3u8 里的相对/绝对地址改写成同源代理地址。

    HLS 由 hls.js 通过 XHR 拉取，跨域会被拦截；同时分片里的相对路径
    也必须相对原始 m3u8 解析，否则拿不到分片。
    """
    out = []

    def to_proxy(abs_url: str) -> str:
        path = urllib.parse.urlparse(abs_url).path.lower()
        prefix = "/hls?url=" if path.endswith(".m3u8") else "/proxy?url="
        return prefix + urllib.parse.quote(abs_url, safe="")

    for line in text.splitlines():
        s = line.strip()
        if not s:
            out.append(line)
            continue
        if s.startswith("#"):
            # EXT-X-KEY / EXT-X-MAP 等带 URI="..." 的属性行
            out.append(
                re.sub(
                    r'URI="([^"]+)"',
                    lambda m: 'URI="%s"'
                    % to_proxy(urllib.parse.urljoin(base_url, m.group(1))),
                    line,
                )
            )
        else:
            out.append(to_proxy(urllib.parse.urljoin(base_url, s)))
    return "\n".join(out) + "\n"


# ---- HLS 广告分片过滤（与 lib/services/hls_ad_filter.dart 同一套规则）----
# 采集站片源的 m3u8 常被注入广告分片，且**与正片同域名、同命名风格**，
# 只有「前后各一条 DISCONTINUITY + 时长异常短」这一个可判据。
AD_EDGE_MAX_SECONDS = 45        # 首尾块判为广告的最长总时长（仅跨域首尾块）
AD_SAME_HOST_EDGE_MAX_SECONDS = 30  # 同域首尾块阈值（更严：可能是片头曲/序幕，
                                    # 误删就是跳剧情；2026-10-18 收紧）
AD_OUTLIER_DOMINANCE = 5        # 判为广告时，典型块时长（中位数）至少是其的倍数
                                # 用中位数而非最长块：某些源把整集切成上百个
                                # 等长短块，此时首尾块相对「最长块」也显得短，
                                # 会被误判成片头/片尾贴片删掉正片。
AD_MIDROLL_MAX_SECONDS = 60     # 中间块判为广告的最长总时长
AD_NEIGHBOR_MIN_SECONDS = 120   # 中间块判为广告时，相邻正片块的最短时长
AD_NEIGHBOR_DOMINANCE = 6       # 中间块判为广告时，相邻正片块至少是其的倍数
AD_MAX_REMOVED_RATIO = 0.5      # 剔除占比上限，超出则整体放弃过滤
# 局部对比判据只在块数很少时启用：块多（等长切分）的源相邻块时长本就有波动，
# 实测会把 5.8s 的正片小段误判成广告。
AD_LOCAL_CONTRAST_MAX_BLOCKS = 8
AD_LOCAL_CONTRAST_MAX_SECONDS = 45   # 局部对比下候选块自身最长时长（2026-10-18 收紧）
AD_LOCAL_CONTRAST_MIN_NEIGHBOR_SUM = 400  # 局部对比下两侧正片时长之和下限

# 内置广告路径特征：**路径段精确匹配**（避免 downloads/ 命中 ads/ 这类误伤）。
# 来自实测注入样本（adjump）与常见贴片广告目录命名。
BUILTIN_AD_PATH_SEGMENTS = frozenset({
    "adjump", "advert", "advertisement", "advertising",
    "preroll", "postroll", "midroll", "adtime", "adpush",
    "adinsert", "adservice", "adserver", "adsrc", "advideo",
    "adzone", "ggad",
})


# 用户可维护广告规则（assets/ad_block_rules.json），懒加载并缓存。
_AD_RULES_CACHE = None


def _load_ad_rules():
    global _AD_RULES_CACHE
    if _AD_RULES_CACHE is not None:
        return _AD_RULES_CACHE
    rules = {
        "blockedHosts": [],
        "blockedUrlSubstrings": [],
        "blockedPathSegments": set(BUILTIN_AD_PATH_SEGMENTS),
        "localContrastRatio": 0.6,
        "maxAdBlockSeconds": 60,
    }
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        path = os.path.join(here, "..", "assets", "ad_block_rules.json")
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        rules["blockedHosts"] = data.get("blockedHosts") or []
        rules["blockedUrlSubstrings"] = data.get("blockedUrlSubstrings") or []
        # 内置特征默认并入，可用 disableBuiltinPathSegments 关闭（排查误删用）。
        segs = set() if data.get("disableBuiltinPathSegments") else set(
            BUILTIN_AD_PATH_SEGMENTS)
        segs |= {str(s).lower() for s in (data.get("blockedPathSegments") or [])}
        rules["blockedPathSegments"] = segs
        rules["localContrastRatio"] = float(
            data.get("localContrastRatio", 0.6))
        rules["maxAdBlockSeconds"] = float(data.get("maxAdBlockSeconds", 60))
    except Exception:
        pass
    _AD_RULES_CACHE = rules
    return rules


def _segment_blocked(url: str, rules) -> bool:
    for h in rules.get("blockedHosts", []):
        if h and h in _host_of(url):
            return True
    for s in rules.get("blockedUrlSubstrings", []):
        if s and s in url:
            return True
    segs = rules.get("blockedPathSegments") or ()
    if segs:
        path = urllib.parse.urlparse(url).path
        for seg in path.split("/"):
            if seg.lower() in segs:
                return True
    return False


def _hls_blocks(text: str, base_url: str):
    """按 #EXT-X-DISCONTINUITY 把分片切成块，返回 [(时长, [绝对url...]), ...]。

    相对路径必须先解析成绝对地址，否则取不到域名、无法做跨域比对。
    """
    blocks = [[]]
    duration = 0.0
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#EXTINF:"):
            try:
                duration = float(line[len("#EXTINF:"):].split(",")[0])
            except ValueError:
                duration = 0.0
        elif line.startswith("#EXT-X-DISCONTINUITY"):
            blocks.append([])
        elif not line.startswith("#"):
            blocks[-1].append((duration,
                               urllib.parse.urljoin(base_url, line)))
    return blocks


def _host_of(url: str) -> str:
    return urllib.parse.urlparse(url).hostname or ""


def _dominant_host(entries) -> str:
    """按总时长加权统计主体域名（不用分片个数，短广告片会顶翻正片）。"""
    weights = {}
    for duration, url in entries:
        host = _host_of(url)
        if not host:
            continue
        weights[host] = weights.get(host, 0.0) + duration
    if not weights:
        return ""
    return max(weights.items(), key=lambda kv: kv[1])[0]


def _rebuild_playlist(blocks, non_empty, is_ad, rule_removed_urls):
    """按保留的分片重建一份去广告播放列表（跳过 is_ad 块与规则命中的分片）。

    与 lib/services/hls_ad_filter.dart 的 buildAdFreePlaylistContent 逐字对齐：
    仅当「当前分片的前一个原始分片也被保留」时，才保留其前的 #EXT-X-DISCONTINUITY。
    否则该 discontinuitiy 原本是正片→广告边界，广告剔除后两侧已是连续正片，留着会让
    播放器越过时重置解码器 → "Error decoding audio" 反复报错 / 闪退。
    """
    # 按原始顺序扁平化，记录每块分片 (block_index, 时长, url, 是否保留, 原始序号)。
    flat = []
    orig_idx = 0
    for i, block in enumerate(blocks):
        for d, u in block:
            kept = (not is_ad[i]) and (u not in rule_removed_urls)
            flat.append((i, d, u, kept, orig_idx))
            orig_idx += 1
    kept_mask = [f[3] for f in flat]

    out = ["#EXTM3U", "#EXT-X-VERSION:3",
           "#EXT-X-PLAYLIST-TYPE:VOD", "#EXT-X-MEDIA-SEQUENCE:0"]
    target = 10
    for _, d, _, kept, _ in flat:
        if kept:
            target = max(target, math.ceil(d))
    out.insert(2, "#EXT-X-TARGETDURATION:%d" % target)

    prev_block = None
    for i, d, u, kept, orig_idx in flat:
        if not kept:
            continue
        # 仅当「前一个原始分片也保留」时，才保留其前的 DISCONTINUITY。
        prev_original_kept = orig_idx > 0 and kept_mask[orig_idx - 1]
        if prev_block is not None and i != prev_block and prev_original_kept:
            out.append("#EXT-X-DISCONTINUITY")
        prev_block = i
        out.append("#EXTINF:%.3f," % d)
        out.append(u)
    out.append("#EXT-X-ENDLIST")
    return "\n".join(out) + "\n"


def filter_m3u8_ads(base_url: str, text: str):
    """剔除媒体播放列表里的广告分片，返回 (新文本, 剔除片数, 剔除秒数)。

    仅处理 VOD 列表；判定可疑时原样返回，宁可放过也不误删正片。

    两级防御（与 lib/services/hls_ad_filter.dart 同一套）：
      pass0 规则清单（assets/ad_block_rules.json + 内置路径特征）：命中域名 /
            URL 子串 / URL 路径段（如 adjump）的分片一律判广告，优先级最高，
            用于覆盖「同域名、等长切块、无 DISCONTINUITY」这类死区；
      pass1/pass2 启发式：跨域块 + 首尾短块 + 中插全局离群短块。
    """
    upper = text.upper()
    if "#EXT-X-ENDLIST" not in upper:
        return text, 0, 0.0
    # 加密流 / 初始化分片 / 字节区间流：重建列表会丢掉这些标签导致播不了，
    # 宁可放过广告也不改坏播放。
    for tag in ("#EXT-X-KEY", "#EXT-X-MAP", "#EXT-X-BYTERANGE"):
        if tag in upper:
            return text, 0, 0.0

    rules = _load_ad_rules()
    has_rules = bool(rules.get("blockedHosts")
                     or rules.get("blockedUrlSubstrings")
                     or rules.get("blockedPathSegments"))

    blocks = _hls_blocks(text, base_url)
    non_empty = [i for i, b in enumerate(blocks) if b]
    if len(non_empty) <= 1:
        # 单块（无 DISCONTINUITY）：启发式无信号，仅规则清单能起作用。
        if not has_rules:
            return text, 0, 0.0
        kept = []
        removed_cnt = 0
        removed_seconds = 0.0
        total_seconds = 0.0
        for i in non_empty:
            for d, u in blocks[i]:
                total_seconds += d
                if _segment_blocked(u, rules):
                    removed_cnt += 1
                    removed_seconds += d
                else:
                    kept.append((d, u))
        if not kept or (total_seconds > 0
                        and removed_seconds > total_seconds * AD_MAX_REMOVED_RATIO):
            return text, 0, 0.0
        out = ["#EXTM3U", "#EXT-X-VERSION:3",
               "#EXT-X-PLAYLIST-TYPE:VOD", "#EXT-X-MEDIA-SEQUENCE:0"]
        target = 10
        for d, _ in kept:
            target = max(target, math.ceil(d))
        out.insert(2, "#EXT-X-TARGETDURATION:%d" % target)
        for d, u in kept:
            out.append("#EXTINF:%.3f," % d)
            out.append(u)
        out.append("#EXT-X-ENDLIST")
        return "\n".join(out) + "\n", removed_cnt, removed_seconds

    durations = [sum(d for d, _ in b) for b in blocks]
    longest = max(non_empty, key=lambda i: durations[i])
    content_host = _dominant_host(blocks[longest]) or _dominant_host(
        [e for b in blocks for e in b])
    if not content_host:
        return text, 0, 0.0

    total = sum(durations[i] for i in non_empty)
    # 典型块时长：非空块时长的中位数（上中位数）。等长切分的片源没有离群块，
    # 因此不会有任何块被判为广告。
    ordered = sorted(durations[i] for i in non_empty)
    median_block = ordered[len(ordered) // 2]
    is_ad = [False] * len(blocks)

    def dominant(i):
        return total > 0 and durations[i] * 2 > total

    def outlier(i):
        return durations[i] * AD_OUTLIER_DOMINANCE <= median_block

    for p, i in enumerate(non_empty):
        if dominant(i):
            continue
        is_edge = p in (0, len(non_empty) - 1)
        if all(_host_of(u) != content_host for _, u in blocks[i]):
            # 跨域块还必须「够短」：多 CDN 分发正片时，长的异域块是正片，
            # 删了就是跳剧情（2026-10-18 用户反馈修复）。首尾跨域块用更严阈值。
            cap = AD_EDGE_MAX_SECONDS if is_edge else max(
                AD_MIDROLL_MAX_SECONDS, rules.get("maxAdBlockSeconds", 60))
            if durations[i] <= cap:
                is_ad[i] = True
            continue
        # 同域首尾块：阈值收紧到 30s，30~45s 的片头曲/序幕更可能是正片。
        if is_edge and durations[i] <= AD_SAME_HOST_EDGE_MAX_SECONDS \
                and outlier(i):
            is_ad[i] = True

    for p, i in enumerate(non_empty):
        if is_ad[i] or p in (0, len(non_empty) - 1) or dominant(i):
            continue
        prev = next_ = None
        for q in range(p - 1, -1, -1):
            if not is_ad[non_empty[q]]:
                prev = durations[non_empty[q]]
                break
        for q in range(p + 1, len(non_empty)):
            if not is_ad[non_empty[q]]:
                next_ = durations[non_empty[q]]
                break
        if prev is None or next_ is None:
            continue
        cap = max(AD_MIDROLL_MAX_SECONDS, rules.get("maxAdBlockSeconds", 60))
        if durations[i] > cap:
            continue
        threshold = max(AD_NEIGHBOR_MIN_SECONDS,
                        durations[i] * AD_NEIGHBOR_DOMINANCE)
        by_global = outlier(i) and prev >= threshold and next_ >= threshold
        ratio = rules.get("localContrastRatio", 0.6)
        # 局部对比闸门（缺一不可，2026-10-18 收紧）：
        # 块数少；两侧正片够长且之和够长；本块够短（更像贴片而非正片分段）。
        by_local = (len(non_empty) <= AD_LOCAL_CONTRAST_MAX_BLOCKS
                    and durations[i] <= AD_LOCAL_CONTRAST_MAX_SECONDS
                    and prev >= AD_NEIGHBOR_MIN_SECONDS
                    and next_ >= AD_NEIGHBOR_MIN_SECONDS
                    and prev + next_ >= AD_LOCAL_CONTRAST_MIN_NEIGHBOR_SUM
                    and durations[i] < prev * ratio
                    and durations[i] < next_ * ratio)
        if by_global or by_local:
            is_ad[i] = True

    # pass0：规则清单命中的分片（片段级）一律判广告，优先级高于启发式。
    rule_removed_urls = set()
    if has_rules:
        for i in non_empty:
            for d, u in blocks[i]:
                if _segment_blocked(u, rules):
                    rule_removed_urls.add(u)

    removed_seconds = sum(durations[i] for i in non_empty if is_ad[i])
    for i in non_empty:
        for d, u in blocks[i]:
            if u in rule_removed_urls:
                removed_seconds += d
    kept_total = sum(durations[i] for i in non_empty if not is_ad[i])
    if kept_total <= 0 or (total > 0
                          and removed_seconds > total * AD_MAX_REMOVED_RATIO):
        return text, 0, 0.0
    if not any(is_ad) and not rule_removed_urls:
        return text, 0, 0.0

    removed_cnt = sum(len(blocks[i]) for i in non_empty if is_ad[i])
    removed_cnt += sum(
        1 for i in non_empty for d, u in blocks[i] if u in rule_removed_urls)
    return _rebuild_playlist(blocks, non_empty, is_ad, rule_removed_urls), \
        removed_cnt, removed_seconds


class ProxyMixin:
    """把 /proxy（通用转发）与 /hls（m3u8 重写）混入静态文件处理器。"""

    def _cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods",
                         "GET, POST, HEAD, OPTIONS")
        self.send_header("Access-Control-Allow-Headers",
                         "Content-Type, Range, Authorization, Api-Key")
        self.send_header("Access-Control-Expose-Headers",
                         "Content-Length, Content-Range, Content-Type")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")

    def _send_body(self, body: bytes, content_type: str, status: int):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self._cors_headers()
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _fail(self, status: int, message: str):
        body = message.encode("utf-8", "replace")
        self._send_body(body, "text/plain; charset=utf-8", status)

    def _try_image_fallback(self, target: str) -> bool:
        """源站直连失败时的图片兜底：改用公共图片代理拉取。

        某些图床在特定网络下会被 TLS 重置（连接建立后被 RST），
        但公共图片代理的服务器可以直连源站，且返回带 CORS 头的结果，
        浏览器即可正常渲染。成功返回 True，失败返回 False。
        """
        if not urllib.parse.urlparse(target).path.lower().endswith(IMAGE_EXTS):
            return False
        proxied = IMAGE_FALLBACK_TEMPLATE.format(
            urllib.parse.quote(target, safe="")
        )
        try:
            with urllib.request.urlopen(
                proxied, timeout=IMAGE_FALLBACK_TIMEOUT
            ) as resp:
                body = resp.read(MAX_UPSTREAM_BYTES)
                content_type = resp.headers.get("Content-Type", "image/jpeg")
        except Exception as e:  # noqa: BLE001
            print(f"[img ] fallback failed: {e} {target[:90]}", flush=True)
            return False
        if not body:
            return False
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "public, max-age=86400")
        self._cors_headers()
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)
        print(f"[img ] {len(body)}B via fallback {target[:90]}", flush=True)
        return True

    def do_OPTIONS(self):  # noqa: N802 （http.server 的固定命名）
        self.send_response(204)
        self._cors_headers()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_HEAD(self):  # noqa: N802
        if self._is_proxy_path():
            return self._handle_proxy()
        return SimpleHTTPRequestHandler.do_HEAD(self)

    def do_GET(self):  # noqa: N802
        if self._is_proxy_path():
            return self._handle_proxy()
        if self.path.split("?", 1)[0].rstrip("/").endswith(
                "flutter_bootstrap.js"):
            return self._serve_flutter_bootstrap()
        return SimpleHTTPRequestHandler.do_GET(self)

    def _is_proxy_path(self) -> bool:
        return self._proxy_kind() is not None

    def _proxy_kind(self) -> str:
        """返回当前请求的代理类型：proxy / hls / None。"""
        path = self.path.split("?", 1)[0].rstrip("/")
        if path in ("/proxy", "/api/proxy"):
            return "proxy"
        if path in ("/hls", "/api/hls"):
            return "hls"
        return None

    def _serve_flutter_bootstrap(self):
        """返回注入 useLocalCanvasKit 的 flutter_bootstrap.js。

        默认 Flutter Web 的 CanvasKit 从 www.gstatic.com 远程加载，
        在部分网络环境（公司代理/沙箱）该域名被封锁或返回空响应，
        导致渲染器无法初始化、页面卡在"正在加载..."或出现灰屏。
        这里把 buildConfig 里的 useLocalCanvasKit 置 true，
        让 CanvasKit 改从 build/web/canvaskit 本地加载（构建已随产物产出）。
        """
        path = os.path.join(self.directory, "flutter_bootstrap.js")
        try:
            with open(path, "rb") as f:
                raw = f.read().decode("utf-8")
        except OSError:
            return self._fail(404, "flutter_bootstrap.js not found")
        # 注入 useLocalCanvasKit: true —— 在 engineRevision 之前插入
        marker = '"engineRevision":'
        if '"useLocalCanvasKit":true' not in raw and marker in raw:
            raw = raw.replace(marker, '"useLocalCanvasKit":true,' + marker, 1)
        body = raw.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/javascript; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._cors_headers()
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)
        print("[boot] injected useLocalCanvasKit=true", flush=True)

    def _handle_proxy(self):
        if self._proxy_kind() == "hls":
            return self._handle_hls()

        query = urllib.parse.urlparse(self.path).query
        params = urllib.parse.parse_qs(query)
        target = (params.get("url") or [""])[0]
        if not target:
            return self._fail(400, "missing 'url' parameter")

        parsed = urllib.parse.urlparse(target)
        if parsed.scheme not in ALLOWED_SCHEMES:
            return self._fail(400, f"unsupported scheme: {parsed.scheme}")

        headers = {
            "User-Agent": (params.get("ua") or [DEFAULT_UPSTREAM_UA])[0],
            "Accept": "*/*",
            # 关掉压缩，省去解压逻辑，也避免部分源站返回异常 gzip
            "Accept-Encoding": "identity",
        }
        referer = (params.get("referer") or [""])[0]
        if referer:
            headers["Referer"] = referer
        origin = (params.get("origin") or [""])[0]
        if origin:
            headers["Origin"] = origin

        # 视频拖动需要 Range 透传
        client_range = self.headers.get("Range")
        if client_range:
            headers["Range"] = client_range

        req = urllib.request.Request(target, headers=headers,
                                     method=self.command)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                body = resp.read(MAX_UPSTREAM_BYTES)
                status = resp.status
                content_type = resp.headers.get(
                    "Content-Type", "application/octet-stream")
                content_range = resp.headers.get("Content-Range")
                accept_ranges = resp.headers.get("Accept-Ranges")
        except urllib.error.HTTPError as e:
            body = e.read(MAX_UPSTREAM_BYTES) if e.fp else b""
            status = e.code
            content_type = e.headers.get(
                "Content-Type", "text/plain; charset=utf-8")
            content_range = e.headers.get("Content-Range")
            accept_ranges = e.headers.get("Accept-Ranges")
        except Exception as e:  # noqa: BLE001 （网络异常先试图片兜底，再转 502）
            if self._try_image_fallback(target):
                return
            return self._fail(502, f"upstream error: {e}")

        # 源站返回错误状态且是图片时，同样尝试公共图片代理兜底
        if status >= 400 and self._try_image_fallback(target):
            return

        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        if content_range:
            self.send_header("Content-Range", content_range)
        self.send_header("Accept-Ranges", accept_ranges or "bytes")
        self._cors_headers()
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)
        print(f"[proxy] {status} {len(body)}B {target[:110]}", flush=True)

    def _handle_hls(self):
        """拉取 m3u8 并重写其中的地址，使 hls.js 能同源拉流。"""
        query = urllib.parse.urlparse(self.path).query
        params = urllib.parse.parse_qs(query)
        target = (params.get("url") or [""])[0]
        if not target:
            return self._fail(400, "missing 'url' parameter")
        parsed = urllib.parse.urlparse(target)
        if parsed.scheme not in ALLOWED_SCHEMES:
            return self._fail(400, f"unsupported scheme: {parsed.scheme}")

        req = urllib.request.Request(
            target,
            headers={
                "User-Agent": DEFAULT_UPSTREAM_UA,
                "Accept": "*/*",
                "Accept-Encoding": "identity",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read(8 * 1024 * 1024).decode("utf-8", "replace")
        except Exception as e:  # noqa: BLE001
            return self._fail(502, f"upstream error: {e}")

        cleaned, removed, removed_seconds = filter_m3u8_ads(target, raw)
        if removed:
            print(
                f"[hls ] 去广告：剔除 {removed} 片 / {removed_seconds:.1f}s",
                flush=True,
            )
        body = rewrite_m3u8(target, cleaned).encode("utf-8")
        self.send_response(200)
        self.send_header(
            "Content-Type", "application/vnd.apple.mpegurl; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._cors_headers()
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)
        print(f"[hls ] {len(body)}B {target[:110]}", flush=True)


class WebHandler(ProxyMixin, SimpleHTTPRequestHandler):
    """静态托管 + /proxy 转发；未知路径回退到 index.html（SPA 路由）。"""

    def translate_path(self, path):
        # 让 /proxy 之类路径不落到磁盘文件查找
        if self._is_proxy_path():
            return os.path.join(self.directory, "__proxy__")
        return super().translate_path(path)

    def send_error(self, code, message=None, explain=None):
        # SPA 回退：静态文件找不到时给 index.html，交给 Flutter 路由处理
        if code == 404:
            index = os.path.join(self.directory, "index.html")
            if os.path.isfile(index):
                try:
                    with open(index, "rb") as f:
                        body = f.read()
                except OSError:
                    return super().send_error(code, message, explain)
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(body)
                return
        return super().send_error(code, message, explain)

    def end_headers(self):
        # 静态资源同样带 CORS，便于跨域调试。
        # 注意：不要加 Cross-Origin-Embedder-Policy: require-corp —— 它要求所有
        # 子资源都带 CORP 头，且会让 crossOriginIsolated 失效，导致 CanvasKit
        # (Skia WASM) 无法初始化线程、渲染器不产画布、页面卡在 splash/灰屏。
        if not self._is_proxy_path():
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
            # 入口文件不缓存：index.html 里的启动占位层移除逻辑改动后，
            # 若浏览器复用旧副本会继续黑屏/灰屏，误导排查方向。
            path = urllib.parse.urlparse(self.path or "").path.rstrip("/")
            if path.endswith(("index.html", "flutter_bootstrap.js")) or path == "":
                self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
                self.send_header("Pragma", "no-cache")
                self.send_header("Expires", "0")
        super().end_headers()

    def log_message(self, fmt, *args):
        if "/proxy" in (self.path or ""):
            return
        super().log_message(fmt, *args)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--root", default=os.path.join("build", "web"))
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        print(f"!! 静态目录不存在: {root}", flush=True)
        print("   请先执行 flutter build web，或用 --root 指定目录", flush=True)

    handler = lambda *a, **kw: WebHandler(*a, directory=root, **kw)  # noqa: E731
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    ThreadingHTTPServer.daemon_threads = True
    with ThreadingHTTPServer(("0.0.0.0", args.port), handler) as httpd:
        print(f"movie_app Web 已启动: http://127.0.0.1:{args.port}/", flush=True)
        print(f"静态目录: {root}", flush=True)
        print(f"CORS 代理: http://127.0.0.1:{args.port}/proxy?url=<urlencoded>",
              flush=True)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n已停止", flush=True)


if __name__ == "__main__":
    sys.exit(main())
