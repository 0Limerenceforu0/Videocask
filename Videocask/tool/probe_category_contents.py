"""查看某采集站某分类下的内容构成（判断该分类是否混装）。

用法：
    python tool/probe_category_contents.py <源名> <分类名关键词> [页数]

例：
    python tool/probe_category_contents.py ffzy 国产动漫 2

用于回答：熊猫头 / 手绘沙雕动画到底被采集站塞进了哪个分类，
以及那个分类里是"全是沙雕"还是"混着正经国漫"（决定过滤策略）。
"""
import json
import sys
import time
import urllib.parse
import urllib.request

SOURCES = {
    "ffzy": "https://cj.ffzyapi.com/api.php/provide/vod/from/ffm3u8/",
    "bfzy": "https://bfzyapi.com/api.php/provide/vod/from/bfzym3u8/",
    "lzi": "https://cj.lziapi.com/api.php/provide/vod/from/lzm3u8/",
    "hongniu": "https://www.hongniuzy2.com/api.php/provide/vod/from/hnm3u8/",
}
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}


def get(base: str, params: dict, timeout: int = 20) -> dict:
    sep = "&" if "?" in base else "?"
    url = f"{base}{sep}" + urllib.parse.urlencode(params, encoding="utf-8")
    with urllib.request.urlopen(
        urllib.request.Request(url, headers=UA), timeout=timeout
    ) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else "ffzy"
    key = sys.argv[2] if len(sys.argv) > 2 else "国产动漫"
    pages = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    base = SOURCES[src]

    classes = get(base, {"ac": "list"}).get("class", []) or []
    hits = [c for c in classes if key in str(c.get("type_name", ""))]
    print(f"[{src}] 分类名含「{key}」的节点：")
    for c in hits:
        print(f"  id={c.get('type_id')} name={c.get('type_name')}")
    if not hits:
        return

    for c in hits:
        tid = c["type_id"]
        print(f"\n--- 分类 {tid} {c.get('type_name')} 内容抽样 ---")
        for pg in range(1, pages + 1):
            d = get(base, {"ac": "detail", "t": tid, "pg": pg})
            print(f"  第{pg}页 total={d.get('total')} 本页{len(d.get('list', []) or [])}条")
            for m in (d.get("list", []) or [])[:20]:
                print(f"    - {m.get('vod_name')} | class={m.get('vod_class')}")
            time.sleep(0.4)


if __name__ == "__main__":
    main()
