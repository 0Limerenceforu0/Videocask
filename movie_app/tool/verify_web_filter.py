# -*- coding: utf-8 -*-
"""验证 web_dev_server.py 的 filter_m3u8_ads 与 Dart 端 hls_ad_filter.dart 行为一致。

不依赖 Flask/Dart，直接 import 模块函数跑断言。运行：
  python tool/verify_web_filter.py
"""

import os
import sys

# 让脚本能直接 import 同目录的 web_dev_server 模块
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import web_dev_server as srv


def build(blocks):
    """blocks: List[List[(duration, url)]]；按 DISCONTINUITY 拼成 m3u8 文本。"""
    lines = ["#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-TARGETDURATION:10",
             "#EXT-X-MEDIA-SEQUENCE:0"]
    for b in blocks:
        if not b:
            lines.append("#EXT-X-DISCONTINUITY")
            continue
        for d, u in b:
            lines.append("#EXTINF:%.3f," % d)
            lines.append(u)
        lines.append("#EXT-X-DISCONTINUITY")
    lines[-1] = "#EXT-X-ENDLIST"
    return "\n".join(lines) + "\n"


def count_segments(text):
    return sum(1 for ln in text.splitlines() if ln.strip()
               and not ln.strip().startswith("#"))


PASS = 0
FAIL = 0


def check(name, cond):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  PASS  " + name)
    else:
        FAIL += 1
        print("  FAIL  " + name)


# ---- 用例 1：单块 + URL 子串规则 → 命中（pass0，死区唯一解法）----
base = "https://v.example.com/play/123/"
text = build([[(10.0, base + "seg001.ts"), (10.0, base + "seg002.ts"),
               (10.0, "https://ad-cdn.net/ad/ad1.ts"),
               (10.0, base + "seg003.ts")]])
# 临时用一个含规则的 rules（通过 _AD_RULES_CACHE 直接注入）
srv._AD_RULES_CACHE = {"blockedHosts": ["ad-cdn.net"],
                       "blockedUrlSubstrings": []}
cleaned, removed, secs = srv.filter_m3u8_ads(base, text)
check("单块+域名规则拦截 1 片", removed == 1 and "ad-cdn.net" not in cleaned
      and count_segments(cleaned) == 3)
srv._AD_RULES_CACHE = None  # 复位

# ---- 用例 2：单块无规则 → 原样返回（启发式无信号）----
srv._AD_RULES_CACHE = {"blockedHosts": [], "blockedUrlSubstrings": []}
text2 = build([[(10.0, base + "a.ts"), (10.0, base + "b.ts")]])
cleaned2, removed2, _ = srv.filter_m3u8_ads(base, text2)
check("单块无规则不误删", removed2 == 0 and count_segments(cleaned2) == 2)
srv._AD_RULES_CACHE = None

# ---- 用例 3：跨域广告块（多块）→ 启发式 pass1 即拦 ----
text3 = build([
    [(30.0, "https://v.example.com/main1.ts")],
    [(15.0, "https://ads.evil.com/x1.ts"), (15.0, "https://ads.evil.com/x2.ts")],
    [(30.0, "https://v.example.com/main2.ts")],
])
# 规则为空，纯启发式
srv._AD_RULES_CACHE = {"blockedHosts": [], "blockedUrlSubstrings": []}
cleaned3, removed3, secs3 = srv.filter_m3u8_ads(base, text3)
check("跨域广告块启发式拦截 2 片", removed3 == 2
      and "ads.evil.com" not in cleaned3
      and count_segments(cleaned3) == 2)
srv._AD_RULES_CACHE = None

# ---- 用例 4：同域等长切块（无 DISCONTINUITY）→ 零误删 ----
equal = [[(20.1, base + "s%03d.ts" % i)] for i in range(146)]
text4 = build(equal)
srv._AD_RULES_CACHE = {"blockedHosts": [], "blockedUrlSubstrings": []}
cleaned4, removed4, _ = srv.filter_m3u8_ads(base, text4)
check("146 等长短块零误删", removed4 == 0 and count_segments(cleaned4) == 146)
srv._AD_RULES_CACHE = None

# ---- 用例 5：同域等长切块 + 规则命中固定广告子串 → 只删命中的 ----
# 第 40、80、120 片用 /ad/ 子串，其余 /s/
mix = []
for i in range(146):
    if i in (40, 80, 120):
        mix.append([(20.1, "https://v.example.com/ad/ad%d.ts" % i)])
    else:
        mix.append([(20.1, "https://v.example.com/s/s%03d.ts" % i)])
text5 = build(mix)
srv._AD_RULES_CACHE = {"blockedHosts": [],
                       "blockedUrlSubstrings": ["/ad/"]}
cleaned5, removed5, _ = srv.filter_m3u8_ads(base, text5)
check("同域等长 + /ad/ 规则只删 3 片", removed5 == 3
      and count_segments(cleaned5) == 143
      and "/ad/" not in cleaned5)
srv._AD_RULES_CACHE = None

# ---- 用例 6：单块规则把全部命中 → 占比超 50% 兜底放弃 ----
# 故意把整段都标成广告域名，应整体放弃过滤（不删光）
text6 = build([[(10.0, "https://ad-cdn.net/a.ts"),
               (10.0, "https://ad-cdn.net/b.ts")]])
srv._AD_RULES_CACHE = {"blockedHosts": ["ad-cdn.net"],
                       "blockedUrlSubstrings": []}
cleaned6, removed6, _ = srv.filter_m3u8_ads(base, text6)
check("整段命中规则 → 50% 兜底放弃", removed6 == 0
      and count_segments(cleaned6) == 2)
srv._AD_RULES_CACHE = None

# ---- 用例 7：规则命中块内个别分片（多块）→ 精准剔除不丢 DISCONTINUITY ----
text7 = build([
    [(30.0, "https://v.example.com/m1.ts")],
    [(20.0, "https://v.example.com/n1.ts"),
     (20.0, "https://v.example.com/ad/spot.ts"),
     (20.0, "https://v.example.com/n2.ts")],
    [(30.0, "https://v.example.com/m2.ts")],
])
srv._AD_RULES_CACHE = {"blockedHosts": [],
                       "blockedUrlSubstrings": ["/ad/"]}
cleaned7, removed7, _ = srv.filter_m3u8_ads(base, text7)
check("块内规则命中 1 片精准剔除", removed7 == 1
      and count_segments(cleaned7) == 4
      and "spot.ts" not in cleaned7)
srv._AD_RULES_CACHE = None

print("\n结果: %d 通过 / %d 失败" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
