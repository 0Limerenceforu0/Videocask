# -*- coding: utf-8 -*-
"""下载《给阿嬷的情书》被剔除的 18 个广告分片，合成 mp4 留样。

流程与 tool/extract_ad_samples.py 一致：先按字节拼接成单个 .ts，
再 ffmpeg 转封装（本机 ffmpeg 无 concat 解封装/无 aac，只能这么干）。
"""
import json
import os
import subprocess
import sys

FFMPEG = r"D:\Trae CN\resources\app\bin\ffmpeg.exe"
WORK = r"C:/Users/Wang/AppData/Local/Temp/hls_debug"
OUT_DIR = r"D:/flutter-dome/movie_app/movie_app/deliverables/ad_samples"


def main():
    with open(os.path.join(WORK, "ad_blocks.json"), encoding="utf-8") as f:
        data = json.load(f)

    segs = []
    for b in data["adBlocks"]:
        segs.extend(b["segments"])
    print("共 %d 个广告分片，合计 %.1fs" % (len(segs), data["removedSeconds"]))

    ts_files = []
    for i, s in enumerate(segs):
        url = s["url"]
        path = os.path.join(WORK, "ad_%03d.ts" % i)
        r = subprocess.run(
            ["curl", "-s", "--max-time", "40", "-o", path, url],
            capture_output=True,
        )
        size = os.path.getsize(path) if os.path.exists(path) else 0
        if size == 0:
            print("  下载失败: %s" % url)
            sys.exit(1)
        ts_files.append(path)
        print("  [%2d/%d] %7d B  %s" % (i + 1, len(segs), size, url.rsplit("/", 1)[-1]))

    combined = os.path.join(WORK, "ad_combined.ts")
    with open(combined, "wb") as out:
        for p in ts_files:
            with open(p, "rb") as f:
                out.write(f.read())
    print("拼接完成: %.1f MB" % (os.path.getsize(combined) / 1048576))

    out_mp4 = os.path.join(OUT_DIR, "11_给阿嬷的情书_被剔除广告_74s.mp4")
    # 优先流拷贝；失败回退 libx264 重编码。
    for extra in (["-c:v", "copy", "-an"], ["-c:v", "libx264", "-preset", "veryfast", "-an"]):
        cmd = [FFMPEG, "-hide_banner", "-loglevel", "error", "-y",
               "-i", combined, "-map", "0:v:0"] + extra + [out_mp4]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode == 0 and os.path.exists(out_mp4) and os.path.getsize(out_mp4) > 0:
            print("合成成功(%s): %s (%.1f MB)" % (" ".join(extra), out_mp4, os.path.getsize(out_mp4) / 1048576))
            return
        print("  方式失败 %s: %s" % (" ".join(extra), (r.stderr or "")[:200]))
    sys.exit(1)


if __name__ == "__main__":
    main()
