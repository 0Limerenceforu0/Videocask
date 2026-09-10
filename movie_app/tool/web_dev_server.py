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

        body = rewrite_m3u8(target, raw).encode("utf-8")
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
