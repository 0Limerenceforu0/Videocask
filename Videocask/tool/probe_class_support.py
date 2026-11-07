# -*- coding: utf-8 -*-
"""确认 `class` 筛选到底是 ffzy 私有扩展，还是各源通用（换参数名能否生效）。

意义：若其他 5 源也能用，就能"用站点自己的标签"替代关键词判别器（一劳永逸）；
若只有 ffzy 能用，那 class 筛选只能当"锦上添花"，主力仍是判别器。

用法：python tool/probe_class_support.py
"""
import json
import time
import urllib.parse
import urllib.request

UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126.0 Safari/537.36"}

CASES = [
    ("红牛资源", "https://www.hongniuzy2.com/api.php/provide/vod/from/hnm3u8/", 36),
    ("量子资源", "https://cj.lziapi.com/api.php/provide/vod/from/lzm3u8/", 29),
    ("暴风资源", "https://bfzyapi.com/api.php/provide/vod/from/bfzym3u8/", 40),
]

VARIANTS = [
    ("detail + class=搞笑", {"ac": "detail", "class": "搞笑"}),
    ("videolist + class=搞笑", {"ac": "videolist", "class": "搞笑"}),
    ("detail + at=搞笑 (类型名)", {"ac": "detail", "at": "搞笑"}),
    ("detail + lang=国语", {"ac": "detail", "lang": "国语"}),
    ("detail + letter=A", {"ac": "detail", "letter": "A"}),
    ("detail + state=完结", {"ac": "detail", "state": "完结"}),
]


def get(base, params, timeout=25):
    sep = "&" if "?" in base else "?"
    url = f"{base}{sep}" + urllib.parse.urlencode(params, encoding="utf-8")
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def main() -> None:
    for name, base, tid in CASES:
        print(f"\n##### {name}（t={tid}） #####")
        base_params = {"t": tid, "pg": 1}
        try:
            b = get(base, {"ac": "detail", **base_params})
            baseline = b.get("total")
        except Exception as e:  # noqa: BLE001
            print(f"  基线失败: {e}")
            continue
        print(f"  基线 total={baseline}")
        for label, extra in VARIANTS:
            params = {**base_params, **extra}
            try:
                d = get(base, params)
                t = d.get("total")
                mark = "✓ 生效" if t != baseline else "— 忽略"
                print(f"    {label:28s} total={t}  {mark}")
            except Exception as e:  # noqa: BLE001
                print(f"    {label:28s} ✗ {e}")
            time.sleep(0.35)


if __name__ == "__main__":
    main()
