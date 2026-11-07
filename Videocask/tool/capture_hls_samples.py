"""抓取采集站真实 m3u8 样本，用于刷新 test/fixtures/hls/ 下的回归样本。

用法：
    python tool/capture_hls_samples.py 凡人修仙传

会依次：
  1. 调采集站搜索接口拿 vod_play_url；
  2. 对前 N 集的 index.m3u8 取流（master 列表会自动降到一个 variant）；
  3. 打印每份样本的「块结构」（DISCONTINUITY 切分后的 片数/时长），
     人工判断哪些含广告、哪些是反例；
  4. 把原始内容写到 test/fixtures/hls/ 下（默认只打印不落盘，
     确认后加 --write 才写入）。

样本过期（采集站改版）时用它重新抓，覆盖同名文件，再跑
`flutter test test/services/hls_ad_filter_real_sample_test.dart`。
"""

from __future__ import annotations

import argparse
import json
import os
import ssl
import sys
import urllib.parse
import urllib.request

API = "https://cj.ffzyapi.com/api.php/provide/vod/from/ffm3u8/"
HEADERS = {
    "User-Agent": "Mozilla/5.0",
    "Referer": "https://cj.ffzyapi.com/",
}
FIXTURE_DIR = os.path.join("test", "fixtures", "hls")


def _get(url: str) -> str:
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(url, headers=HEADERS)
    return urllib.request.urlopen(req, timeout=25, context=ctx).read().decode(
        "utf-8", "ignore"
    )


def _resolve_media(url: str) -> str:
    """master 列表 → 第一个 variant 的 media 列表原文。"""
    text = _get(url)
    if "#EXT-X-STREAM-INF" in text.upper():
        variants = [
            line.strip()
            for line in text.splitlines()
            if line.strip() and not line.startswith("#")
        ]
        if not variants:
            raise RuntimeError("master 列表里没有 variant")
        url = urllib.parse.urljoin(url, variants[0])
        text = _get(url)
    return text


def _blocks(text: str):
    """按 DISCONTINUITY 切块，返回 [(片数, 总时长), ...]（只保留非空块）。"""
    result = []
    current = []
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
            result.append(current)
            current = []
        elif not line.startswith("#"):
            current.append(duration)
    result.append(current)
    return [(len(b), sum(b)) for b in result if b]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("keyword", help="搜索关键词，如 凡人修仙传")
    parser.add_argument("--episodes", type=int, default=3, help="每部抓几集")
    parser.add_argument("--titles", type=int, default=3, help="抓前几部影片")
    parser.add_argument("--write", action="store_true", help="落盘到 fixtures")
    args = parser.parse_args()

    search = "%s?ac=detail&wd=%s&pg=1" % (
        API.rstrip("/"),
        urllib.parse.quote(args.keyword),
    )
    data = json.loads(_get(search))
    movies = data.get("list") or []
    if not movies:
        print("搜索无结果：", args.keyword)
        return 1

    for movie in movies[: args.titles]:
        play_url = movie.get("vod_play_url") or ""
        episodes = [
            seg.split("$")[-1]
            for seg in play_url.split("#")
            if "$" in seg
        ][: args.episodes]
        print("=== %s (%d 集)" % (movie.get("vod_name"), len(episodes)))
        for index, url in enumerate(episodes, start=1):
            try:
                text = _resolve_media(url)
            except Exception as exc:  # noqa: BLE001
                print("   第%d集 ERR %s" % (index, exc))
                continue
            blocks = _blocks(text)
            segments = sum(count for count, _ in blocks)
            host = urllib.parse.urlparse(url).netloc.replace(".", "_")
            vid = url.rstrip("/").split("/")[-2].replace(".", "")
            name = "real_%s_%s_e%d.m3u8" % (host, vid[:12], index)
            print("   %s: %d 片 / %d 块" % (name, segments, len(blocks)))
            for i, (count, total) in enumerate(blocks[:12]):
                print("       块%d: %d片 %.2fs" % (i, count, total))
            if len(blocks) > 12:
                print("       ... 共 %d 块" % len(blocks))
            if args.write:
                os.makedirs(FIXTURE_DIR, exist_ok=True)
                path = os.path.join(FIXTURE_DIR, name)
                with open(path, "w", encoding="utf-8") as handle:
                    handle.write(text)
                print("       已写入 %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
