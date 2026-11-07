#!/usr/bin/env python3
# 实机验证：用修正后的 web_dev_server(8787) 加载详情页 -> 点播放 -> 读取 video 状态 + 截图
import json, time, base64, urllib.request, urllib.parse, sys
from websocket import create_connection

CDP = "127.0.0.1:9222"
APP = "http://127.0.0.1:8787"
DETAIL = f"{APP}/#/detail?id=10548"
OUT_PNG = "tool/verify_player.png"
events = []

def get_json(path):
    with urllib.request.urlopen(f"http://{CDP}{path}", timeout=10) as r:
        return json.loads(r.read())

def post_json(path, body=b""):
    req = urllib.request.Request(f"http://{CDP}{path}", data=body, method="POST")
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read())

targets = get_json("/json")
page = next((t for t in targets if t.get("type") == "page"), None)
if not page:
    print("NO PAGE TARGET"); sys.exit(1)
ws_url = page["webSocketDebuggerUrl"]
ws = create_connection(ws_url, timeout=40)
mid = 0

def send_wait(method, params=None):
    global mid
    mid += 1
    ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        m = json.loads(ws.recv())
        if m.get("id") == mid:
            return m.get("result")
        if m.get("method"):
            if m["method"] == "Runtime.consoleAPICalled":
                try:
                    txt = " ".join(str(a.get("value")) for a in m["params"]["args"])
                    events.append("console:" + m["params"].get("type","log") + ":" + txt[:200])
                except Exception:
                    events.append(m["method"])
            else:
                events.append(m["method"])

send_wait("Runtime.enable")
send_wait("Page.enable")
# 干净重载到详情页
send_wait("Page.navigate", {"url": DETAIL})
time.sleep(18)

STATE = r"""(() => {
  const vs=[...document.querySelectorAll('video')];
  const gp=document.querySelector('flt-glass-pane');
  const cv=gp&&gp.shadowRoot?gp.shadowRoot.querySelector('canvas'):null;
  const splash=document.getElementById('flutter-splash');
  return {
    url: location.hash,
    canvas: cv?[cv.width,cv.height]:null,
    splashDisplay: splash?getComputedStyle(splash).display:'(removed)',
    videoCount: vs.length,
    videos: vs.map(v=>({ct:+v.currentTime.toFixed(2),paused:v.paused,rs:v.readyState,
      vw:v.videoWidth,vh:v.videoHeight,err:v.error?v.error.code:null}))
  };
})()"""

def probe(tag):
    r = send_wait("Runtime.evaluate", {"expression": STATE, "returnByValue": True})
    if r and r.get("exceptionDetails"):
        print(f"[{tag}] EXCEPTION: " + json.dumps(r["exceptionDetails"], ensure_ascii=False)[:400])
        return None
    val = (r or {}).get("result", {}).get("value")
    print(f"[{tag}] " + json.dumps(val, ensure_ascii=False))
    return val

# 诊断：页面元信息
diag = send_wait("Runtime.evaluate", {"expression":
    "({href:location.href, ready:document.readyState, hasGlass:!!document.querySelector('flt-glass-pane'), "
    "hasBootstrap:!!document.querySelector('script[src*=bootstrap]'), ck:typeof window.flutterCanvasKit, "
    "bodyKids:[...document.body.children].map(e=>e.tagName+'.'+(e.className||'')).slice(0,6)})",
    "returnByValue": True})
print("[diag RAW] " + json.dumps(diag, ensure_ascii=False)[:600])

v1 = probe("load")
if not v1 or v1.get("videoCount", 0) == 0 or all(x.get("paused") for x in v1.get("videos", [])):
    vp = send_wait("Runtime.evaluate", {"expression": "({w:innerWidth,h:innerHeight})", "returnByValue": True})
    size = (vp or {}).get("result", {}).get("result", {}).get("value", {"w":1280,"h":720})
    x, y = int(size["w"]*0.5), int(size["h"]*0.5)
    for _ in range(1):
        send_wait("Input.dispatchMouseEvent", {"type":"mousePressed","x":x,"y":y,"button":"left","clickCount":1})
        time.sleep(0.1)
        send_wait("Input.dispatchMouseEvent", {"type":"mouseReleased","x":x,"y":y,"button":"left","clickCount":1})
        time.sleep(1)
    # 多点试探：常见播放按钮靠下中部
    for (xf,yf) in [(0.5,0.62),(0.5,0.5),(0.5,0.78)]:
        xx,yy=int(size["w"]*xf),int(size["h"]*yf)
        send_wait("Input.dispatchMouseEvent", {"type":"mousePressed","x":xx,"y":yy,"button":"left","clickCount":1})
        time.sleep(0.08)
        send_wait("Input.dispatchMouseEvent", {"type":"mouseReleased","x":xx,"y":yy,"button":"left","clickCount":1})
        time.sleep(2)
        v = probe(f"click@{xf},{yf}")
        if v and v.get("videoCount",0)>0 and not all(x.get("paused") for x in v.get("videos",[])):
            break
    time.sleep(6)
    probe("after-click")

# 再采样一次，看 currentTime 是否推进
v_a = probe("sample-A")
time.sleep(4)
v_b = probe("sample-B")

# 强制播放验证：直接调用 video.play()（已静音），采样 currentTime 是否推进
fp = send_wait("Runtime.evaluate", {"expression":
    "(function(){var v=document.querySelector('video');if(!v)return 'no-video';"
    "try{v.muted=true;v.volume=0;var pr=v.play();return 'play-called:'+(v.videoWidth+'x'+v.videoHeight)+':rs'+v.readyState;}catch(e){return 'err:'+e.message;}})()",
    "returnByValue": True})
print("[force-play] " + json.dumps((fp or {}).get("result", {}).get("value", fp)))
time.sleep(6)
probe("after-force-play")

# 截图
try:
    shot = send_wait("Page.captureScreenshot", {"fromSurface": True})
    with open(OUT_PNG, "wb") as f:
        f.write(base64.b64decode(shot["data"]))
    print("[shot] saved", OUT_PNG)
except Exception as e:
    print("[shot] failed", e)

# 控制台错误
print("[console-events] total:", len(events))
for e in events:
    if e.startswith("console:error") or e.startswith("console:warning"):
        print("   !", e[:240])
ws.close()
print("DONE")
