#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从采集站抽取「被本项目去广告逻辑判定为广告」的真实分片，合成 mp4 留样。

用途：给用户直观看到「屏蔽掉的到底是什么」——每部影视出一段 mp4，并说明
广告出现在整集的哪个时间点（片头 / 中插 / 片尾）。

链路：
  采集站搜索 → 取某集 m3u8 →（master 则取子列表）→ 调 dart 工具判定
  → 下载被判广告的分片 → ffmpeg 合成 mp4 → 写报告

用法：
  python tool/extract_ad_samples.py                 # 默认抽 10 部
  python tool/extract_ad_samples.py --limit 10 --out deliverables/ad_samples
  python tool/extract_ad_samples.py --ffmpeg "D:/x/ffmpeg.exe"

注意：判定完全复用生产逻辑（assets/ad_block_rules.json + 内置路径特征），
      不做任何"为了出样而放宽"的改动。
"""

import argparse
import concurrent.futures as futures
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)

# 采集站（与 lib/config 中一致）
SOURCES = [
    ("ffzy", "https://cj.ffzyapi.com/api.php/provide/vod/from/ffm3u8/"),
    ("lzi", "https://cj.lziapi.com/api.php/provide/vod/from/lzm3u8/"),
    ("bfzy", "https://bfzyapi.com/api.php/provide/vod/from/bfzym3u8/"),
    ("hongniu", "https://www.hongniuzy2.com/api.php/provide/vod/from/hnm3u8/"),
    ("suoni", "https://suoniapi.com/api.php/provide/vod/from/subm3u8/"),
]

# 候选关键词（热门影视，覆盖剧集/动漫，尽量多源命中）
KEYWORDS = [
    "凡人修仙传",
    "庆余年",
    "赘婿",
    "狂飙",
    "三体",
    "斗破苍穹",
    "完美世界",
    "开端",
    "隐秘的角落",
    "漫长的季节",
    "雪中悍刀行",
    "甄嬛传",
    "琅琊榜",
    "斗罗大陆",
    "狐妖小红娘",
    "大明王朝",
    "白夜追凶",
    "琅琊榜之风起长林",
    "一人之下",
    "不良人",
    "知否知否应是绿肥红瘦",
    "父母爱情",
    "亮剑",
    "闯关东",
    "山海情",
    "觉醒年代",
]

POSITION_CN = {"head": "片头", "mid": "中插", "tail": "片尾"}


def _enc_url(url):
    """urllib 不能直发含非 ASCII 的 URL（如中文分集路径），先对路径/查询做百分号编码。"""
    if not url:
        return url
    try:
        parts = urllib.parse.urlsplit(url)
        path = urllib.parse.quote(parts.path, safe="/")
        query = urllib.parse.quote(parts.query, safe="=&")
        return urllib.parse.urlunsplit(
            (parts.scheme, parts.netloc, path, query, parts.fragment)
        )
    except Exception:
        return url



# --------------------------------------------------------------------------
# 基础工具
# --------------------------------------------------------------------------
def http_get(url, referer=None, timeout=20, retries=1):
    """GET 文本，失败重试。返回 str 或 None。"""
    headers = {"User-Agent": UA}
    if referer:
        headers["Referer"] = referer
    for i in range(retries + 1):
        try:
            req = urllib.request.Request(_enc_url(url), headers=headers)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read().decode("utf-8", "ignore")
        except Exception as e:
            if i == retries:
                print(f"    ! GET 失败 {type(e).__name__}: {url[:80]}")
                return None
            time.sleep(1.2)


def http_download(url, path, referer=None, timeout=30, retries=2):
    """下载二进制到 path。返回 (ok, bytes)。"""
    headers = {"User-Agent": UA}
    if referer:
        headers["Referer"] = referer
    for i in range(retries + 1):
        try:
            req = urllib.request.Request(_enc_url(url), headers=headers)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = r.read()
        except urllib.error.HTTPError as e:
            if i == retries:
                print(f"    ! HTTP {e.code} 下载失败: {url[:90]}")
                return False, 0
            time.sleep(1.0)
            continue
        except Exception as e:
            if i == retries:
                print(f"    ! {type(e).__name__} 下载失败: {url[:90]}")
                return False, 0
            time.sleep(1.0)
            continue
        # 基本守卫：CDN 返回错误页（403/404 html）时不算成功
        head = data[:256]
        if (
            data[:1] == b"<"
            or data[:5] == b"<?xml"
            or b"404" in head
            or b"403" in head
            or b"Not Found" in head
            or b"Access Denied" in head
        ):
            if i == retries:
                print(f"    ! 返回非媒体内容({len(data)}B) 疑似错误页: {url[:90]}")
                return False, 0
            time.sleep(1.0)
            continue
        with open(path, "wb") as f:
            f.write(data)
        return True, len(data)
    return False, 0


def find_dart(explicit=None):
    """定位 dart 可执行文件。

    Windows 上 flutter/bin/dart 是无扩展名的 shell 脚本，Python 的
    CreateProcess 无法直接执行，因此优先用 dart-sdk 里的 dart.exe。
    """
    if explicit and os.path.isfile(explicit):
        return explicit
    cands = []
    w = shutil.which("dart") or shutil.which("dart.bat")
    if w:
        cands.append(w)
        # 由 flutter/bin/dart(.bat) 推导内置 dart-sdk
        cands.append(
            os.path.join(
                os.path.dirname(w), "cache", "dart-sdk", "bin", "dart.exe"
            )
        )
    cands += [
        r"E:\FultterProject\flutter\bin\cache\dart-sdk\bin\dart.exe",
        r"D:\FultterProject\flutter\bin\cache\dart-sdk\bin\dart.exe",
        r"C:\flutter\bin\cache\dart-sdk\bin\dart.exe",
    ]
    for c in cands:
        if c and os.path.isfile(c):
            return c
    return None


def _ffmpeg_capable(path):
    """ffmpeg 至少要能读 mpegts（广告分片是 .ts）且能编码 libx264（转 mp4）。"""
    if not path or not os.path.isfile(path):
        return False
    try:
        enc = subprocess.run(
            [path, "-hide_banner", "-encoders"],
            capture_output=True, text=True, errors="ignore", timeout=30,
        ).stdout
        dem = subprocess.run(
            [path, "-hide_banner", "-demuxers"],
            capture_output=True, text=True, errors="ignore", timeout=30,
        ).stdout
    except Exception:
        return False
    return ("libx264" in enc) and ("mpegts" in dem)


def find_ffmpeg(explicit=None):
    # 用户显式指定且可用 → 直接用；强制指定（即使功能不全）也尊重用户选择
    if explicit and _ffmpeg_capable(explicit):
        return explicit
    if explicit and os.path.isfile(explicit):
        return explicit
    which = shutil.which("ffmpeg")
    cands = []
    if which:
        cands.append(which)
    cands += [
        r"D:\Trae CN\resources\app\bin\ffmpeg.exe",
        r"D:\进击的巨人\ffmpeg.exe",
        r"C:\Users\Wang\AppData\Local\JianyingPro\Apps\8.9.0.13361\ffmpeg.exe",
    ]
    for c in cands:
        if _ffmpeg_capable(c):
            return c
    for c in cands:
        if os.path.isfile(c):
            return c
    return None


# --------------------------------------------------------------------------
# 采集站：搜索 → 剧集 m3u8
# --------------------------------------------------------------------------
def search_source(source_url, keyword):
    url = (
        source_url
        + "?ac=detail&wd="
        + urllib.parse.quote(keyword)
        + "&pg=1"
    )
    txt = http_get(url, referer=source_url)
    if not txt:
        return []
    try:
        data = json.loads(txt)
    except Exception:
        return []
    return data.get("list") or []


def parse_episodes(vod_play_url):
    """'第01集$url#第02集$url' → [(名称, url)]；多播放组取第一组。"""
    out = []
    if not vod_play_url:
        return out
    for group in vod_play_url.split("$$$"):
        for item in group.split("#"):
            if "$" not in item:
                continue
            name, _, u = item.partition("$")
            u = u.strip()
            if u.lower().startswith("http"):
                out.append((name.strip(), u))
        if out:
            break
    return out


def resolve_media_playlist(m3u8_url):
    """master 列表 → 取子列表（选第一个）；已是媒体列表则原样返回。"""
    txt = http_get(m3u8_url, referer=referer_of(m3u8_url))
    if not txt:
        return None, None
    if "#EXT-X-STREAM-INF" in txt and "#EXTINF" not in txt:
        lines = [l.strip() for l in txt.split("\n") if l.strip()]
        for i, l in enumerate(lines):
            if l.startswith("#EXT-X-STREAM-INF"):
                if i + 1 < len(lines) and not lines[i + 1].startswith("#"):
                    sub = urllib.parse.urljoin(m3u8_url, lines[i + 1])
                    sub_txt = http_get(sub, referer=referer_of(sub))
                    if sub_txt and "#EXTINF" in sub_txt:
                        return sub, sub_txt
    return m3u8_url, txt


def referer_of(url):
    p = urllib.parse.urlparse(url)
    return f"{p.scheme}://{p.hostname}/"


# --------------------------------------------------------------------------
# Dart 判定
# --------------------------------------------------------------------------
def run_dart_extract(m3u8_path, base_url, out_json, dart_exe, timeout=180):
    cmd = [
        dart_exe,
        os.path.join("tool", "hls_ad_extract.dart"),
        m3u8_path,
        base_url,
        out_json,
    ]
    try:
        p = subprocess.run(
            cmd,
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="ignore",
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return None
    if not os.path.isfile(out_json):
        print("    ! dart 抽取失败:", (p.stderr or "")[:300])
        return None
    with open(out_json, "r", encoding="utf-8") as f:
        return json.load(f)


# --------------------------------------------------------------------------
# 下载 + 合成
# --------------------------------------------------------------------------
def download_block_segments(block, workdir, referer, workers=8):
    """并发下载一个广告块的全部分片。返回 (成功路径列表, 失败数)。"""
    segs = block["segments"]
    paths = [None] * len(segs)

    def job(i):
        s = segs[i]
        ext = os.path.splitext(urllib.parse.urlparse(s["url"]).path)[1] or ".ts"
        p = os.path.join(workdir, f"{i:04d}{ext}")
        ok, size = http_download(s["url"], p, referer=referer)
        return i, (p if ok and size > 0 else None)

    with futures.ThreadPoolExecutor(max_workers=workers) as ex:
        for i, p in ex.map(job, range(len(segs))):
            paths[i] = p
    good = [p for p in paths if p]
    good.sort()
    return good, len(segs) - len(good)


def merge_to_mp4(ffmpeg, seg_paths, out_mp4):
    """把若干 .ts 分片合并为 mp4。

    本机自带的 ffmpeg 多为精简构建：可能有 mpegts 解封装与 mp4 封装，但**没有
    concat 解封装器**、也未必有滤镜。因此这里先把所有 .ts 按字节顺序拼接成一个
    合并文件（TS 是流式格式，直接拼即可），再交给 ffmpeg 转封装，避免依赖 concat。

    优先 `-c copy`（不改编码）；失败再回退重编码（需要 libx264）。
    """
    combined = out_mp4 + ".ts"
    try:
        with open(combined, "wb") as w:
            for p in seg_paths:
                with open(p, "rb") as r:
                    while True:
                        buf = r.read(1024 * 1024)
                        if not buf:
                            break
                        w.write(buf)
    except OSError as e:
        print(f"    ! 拼接分片失败: {e}")
        return False

    # 注意：本函数**不删除** combined.ts。本项目跑在批量删除保护钩子下，运行时删除文件
    # 会被 SAFE_DELETE_BULK_CONFIRM_REQUIRED 杀掉。临时文件统一在脚本外用 Bash 清理。

    # 1) 直接 copy（改封装，不依赖编码器）。
    #    广告分片的音频流常常参数缺失（aac 0 声道/无采样率），copy 会失败；
    #    作为留样样例，直接丢弃音频只保留视频最稳。
    cmd_copy = [
        ffmpeg, "-y", "-i", combined,
        "-map", "0:v:0", "-c:v", "copy", "-an", out_mp4,
    ]
    try:
        pc = subprocess.run(
            cmd_copy, capture_output=True, text=True,
            encoding="utf-8", errors="ignore", timeout=600,
        )
    except subprocess.TimeoutExpired:
        print("    ! ffmpeg 超时")
        return False
    if pc.returncode == 0 and os.path.isfile(out_mp4) and os.path.getsize(out_mp4) > 0:
        return True

    # 2) 回退：重编码视频（需要 libx264），同样丢弃音频
    cmd_enc = [
        ffmpeg, "-y", "-i", combined,
        "-map", "0:v:0", "-c:v", "libx264", "-preset", "veryfast", "-crf", "28",
        "-pix_fmt", "yuv420p", "-an",
        "-movflags", "+faststart", out_mp4,
    ]
    try:
        pe = subprocess.run(
            cmd_enc, capture_output=True, text=True,
            encoding="utf-8", errors="ignore", timeout=600,
        )
    except subprocess.TimeoutExpired:
        print("    ! ffmpeg 重编码超时")
        return False
    if pe.returncode == 0 and os.path.isfile(out_mp4) and os.path.getsize(out_mp4) > 0:
        return True

    print("    ! ffmpeg 合并失败（copy 与重编码均失败）:")
    print("      " + (pe.stderr or pe.stdout or pc.stderr or "(无输出)")[-1200:].replace("\n", "\n      "))
    return False


def fmt_hms(sec):
    s = int(round(sec))
    h, s = divmod(s, 3600)
    m, s = divmod(s, 60)
    return f"{h:d}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"


def judge_reason(block):
    """猜测判据来源，仅用于报告说明。"""
    marks = [
        "adjump",
        "advert",
        "preroll",
        "postroll",
        "midroll",
        "adtime",
        "adpush",
        "adinsert",
        "adservice",
        "adserver",
        "adsrc",
        "advideo",
        "adzone",
        "ggad",
    ]
    for s in block["segments"]:
        low = s["url"].lower()
        for m in marks:
            if f"/{m}/" in low:
                return "URL 路径特征命中（内置清单）"
    return "时长/结构启发式（跨域块、离群短块或局部对比）"


# --------------------------------------------------------------------------
# 主流程
# --------------------------------------------------------------------------
def safe_name(name):
    return re.sub(r'[\\/:*?"<>|]+', "_", name).strip()


def try_one(title, source_name, source_url, eps, work, ffmpeg, dart_exe, out_dir, idx):
    """对一部影视尝试抽一集广告。成功返回结果 dict，否则 None。"""
    # 优先试前几集，命中广告即停
    for ep_name, ep_url in eps[:4]:
        print(f"  · {ep_name}")
        media_url, playlist = resolve_media_playlist(ep_url)
        if not playlist or "#EXTINF" not in playlist:
            continue
        if "#EXT-X-KEY" in playlist:
            print("    - 加密流，跳过")
            continue
        m3u8_path = os.path.join(work, "p.m3u8")
        with open(m3u8_path, "w", encoding="utf-8") as f:
            f.write(playlist)
        info = run_dart_extract(
            m3u8_path, media_url, os.path.join(work, "p.json"), dart_exe
        )
        if not info or not info.get("adBlocks"):
            print("    - 该集未检出广告")
            continue

        # 只取最大的那个广告块，避免一段 mp4 里拼太多东西
        block = max(info["adBlocks"], key=lambda b: b["durationSeconds"])
        if block["durationSeconds"] < 3:
            print("    - 广告块过短，跳过")
            continue

        segdir = os.path.join(work, "segs")
        # 注意：不要在这里 rmtree 清理。本项目跑在 WorkBuddy 的「批量删除保护」钩子下，
        # 反复删除大量分片文件会触发 SAFE_DELETE_BULK_CONFIRM_REQUIRED 并杀掉进程。
        # 分片目录只增不清，下载时按序号覆盖同名文件即可（download_block_segments
        # 只引用当集实际下载的那些路径）。
        os.makedirs(segdir, exist_ok=True)
        good, failed = download_block_segments(
            block, segdir, referer=referer_of(media_url)
        )
        if not good:
            print(f"    ! 分片下载全失败（{failed}/{block['segmentCount']}）")
            continue
        if failed:
            print(f"    - {failed}/{block['segmentCount']} 片下载失败，仍继续")

        fname = f"{idx:02d}_{safe_name(title)}_{safe_name(ep_name)}_广告样例.mp4"
        out_mp4 = os.path.join(out_dir, fname)
        if not merge_to_mp4(ffmpeg, good, out_mp4):
            print("    ! ffmpeg 合并失败")
            continue
        size_mb = os.path.getsize(out_mp4) / 1024 / 1024
        print(f"    ✓ {fname}  {size_mb:.1f} MB  起点 {fmt_hms(block['startSeconds'])}")

        return {
            "index": idx,
            "title": title,
            "source": source_name,
            "episode": ep_name,
            "file": fname,
            "size_mb": round(size_mb, 1),
            "total_seconds": info["totalSeconds"],
            "total_hms": fmt_hms(info["totalSeconds"]),
            "position": POSITION_CN.get(block["position"], block["position"]),
            "start_hms": fmt_hms(block["startSeconds"]),
            "start_seconds": block["startSeconds"],
            "ad_seconds": block["durationSeconds"],
            "seg_count": block["segmentCount"],
            "downloaded": len(good),
            "reason": judge_reason(block),
            "sample_url": block["segments"][0]["url"],
            "hosts": block["hosts"],
            "m3u8": media_url,
        }
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=10, help="要抽取的影视数量")
    ap.add_argument("--out", default=os.path.join("deliverables", "ad_samples"))
    ap.add_argument("--ffmpeg", default=None)
    ap.add_argument("--dart", default=None)
    ap.add_argument(
        "--keywords", default=None, help="自定义关键词，逗号分隔，覆盖默认候选"
    )
    ap.add_argument(
        "--sources", default=None, help="限定源站名，逗号分隔，如 ffzy,lzi；默认全部"
    )
    args = ap.parse_args()

    sources = SOURCES
    if args.sources:
        wanted = set(s.strip() for s in args.sources.split(",") if s.strip())
        sources = [s for s in SOURCES if s[0] in wanted]
        if not sources:
            print(f"没有匹配的源站：{args.sources}")
            sys.exit(1)

    ffmpeg = find_ffmpeg(args.ffmpeg)
    if not ffmpeg:
        print("未找到 ffmpeg，请用 --ffmpeg 指定路径")
        sys.exit(1)
    dart_exe = find_dart(args.dart)
    if not dart_exe:
        print("未找到 dart，请用 --dart 指定 dart.exe 路径")
        sys.exit(1)
    print("ffmpeg:", ffmpeg)
    print("dart  :", dart_exe)

    out_dir = os.path.join(ROOT, args.out)
    os.makedirs(out_dir, exist_ok=True)
    work = os.path.join(out_dir, "_work")
    os.makedirs(work, exist_ok=True)

    keywords = (
        [k.strip() for k in args.keywords.split(",") if k.strip()]
        if args.keywords
        else KEYWORDS
    )

    results = []
    used_titles = set()
    idx = 0

    # 轮转源站，避免全压一个源
    for ki, kw in enumerate(keywords):
        if len(results) >= args.limit:
            break
        if kw in used_titles:
            continue
        sname, surl = sources[ki % len(sources)]
        print(f"\n[{len(results)+1}/{args.limit}] {kw}  (源: {sname})")
        vods = search_source(surl, kw)
        if not vods:
            print("  - 搜索无结果")
            continue
        vod = vods[0]
        title = vod.get("vod_name") or kw
        eps = parse_episodes(vod.get("vod_play_url"))
        if not eps:
            print("  - 无 m3u8 剧集")
            continue
        idx += 1
        try:
            r = try_one(title, sname, surl, eps, work, ffmpeg, dart_exe, out_dir, idx)
        except Exception as ex:
            import traceback

            print(f"    ! 处理异常中止: {type(ex).__name__}: {ex}")
            traceback.print_exc()
            idx -= 1
            continue
        if r:
            results.append(r)
            used_titles.add(kw)
        else:
            idx -= 1

    # 报告
    report = os.path.join(out_dir, "广告样例说明.md")
    lines = [
        "# 被屏蔽广告的真实样例",
        "",
        f"抽取时间：{time.strftime('%Y-%m-%d %H:%M')}",
        f"判定逻辑：`lib/services/hls_ad_filter.dart`（与 App 内完全一致，"
        f"含 `assets/ad_block_rules.json` 与内置路径特征）",
        "",
        f"共 {len(results)} 部影视，每部给出该集被判定为广告并剔除的**真实分片**，"
        f"按顺序拼接成一段 mp4。",
        "",
        "| # | 影视 | 集数 | 源站 | 广告位置 | 出现时间点 | 广告时长 | 分片数 | 判据 | 文件 |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    for r in results:
        lines.append(
            f"| {r['index']} | {r['title']} | {r['episode']} | {r['source']} | "
            f"{r['position']} | {r['start_hms']}（整集 {r['total_hms']}） | "
            f"{r['ad_seconds']:.1f}s | {r['downloaded']}/{r['seg_count']} | "
            f"{r['reason']} | `{r['file']}` |"
        )
    lines += ["", "## 明细", ""]
    for r in results:
        lines += [
            f"### {r['index']}. {r['title']} · {r['episode']}",
            "",
            f"- **文件**：`{r['file']}`（{r['size_mb']} MB）",
            f"- **位置**：{r['position']}，出现在整集第 **{r['start_hms']}**"
            f" 处（整集总长 {r['total_hms']}）",
            f"- **时长**：{r['ad_seconds']:.1f} 秒，共 {r['seg_count']} 个分片"
            f"（下载成功 {r['downloaded']} 个）",
            f"- **判据**：{r['reason']}",
            f"- **分片域名**：{', '.join(r['hosts']) or '—'}",
            f"- **播放列表**：`{r['m3u8']}`",
            f"- **首个广告分片**：`{r['sample_url']}`",
            "",
        ]
    lines += [
        "## 说明",
        "",
        "- mp4 内容 = 该集播放列表里被过滤器判定为广告、因而在 App 中**不会播放**"
        "的那几段原始分片，按原顺序拼接。",
        "- 出现时间点按整集所有分片时长累加计算，与 App 进度条上的时间一致。",
        "- 广告分片来自第三方 CDN，若 URL 带时效签名，隔段时间后可能无法重新下载；"
        "样例文件已落地，不受影响。",
    ]
    with open(report, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    # 不在此处 rmtree(work)：避免触发批量删除保护钩子。_work 留待脚本外手动清理。
    print(f"\n完成：{len(results)}/{args.limit} 部")
    print("输出目录:", out_dir)
    print("报告:", report)
    for r in results:
        print(
            f"  {r['index']:>2}. {r['title']} {r['episode']} "
            f"{r['position']} @ {r['start_hms']}  {r['ad_seconds']:.1f}s"
        )


if __name__ == "__main__":
    main()
