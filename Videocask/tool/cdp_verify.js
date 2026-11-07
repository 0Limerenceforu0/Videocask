// CDP 验证脚本：加载页面 → 抓取网络(图片/失败) → 等待 → 截图 → 执行 JS。
// 用法：node tool/cdp_verify.js <url> <waitMs> "<jsExpr>" [screenshotPath]
// 前置：Edge/Chrome 以 --remote-debugging-port=9222 启动（复用已有实例或新建）。
const http = require('http');
const fs = require('fs');

const TARGET = process.argv[2] || 'about:blank';
const WAIT_MS = parseInt(process.argv[3] || '18000', 10);
const EXPR = process.argv[4] || 'document.title';
const SHOT = process.argv[5] || '/tmp/cdp_shot.png';
// 可选：点击（视口比例坐标）→ 用于触发 Flutter Canvas 上的按钮
const CLICK_XF = process.argv[6] ? parseFloat(process.argv[6]) : null;
const CLICK_YF = process.argv[7] ? parseFloat(process.argv[7]) : null;
const WAIT_AFTER_CLICK = parseInt(process.argv[8] || '0', 10);
const PORT = 9222;

const getJson = (path) =>
  new Promise((resolve, reject) => {
    const req = http.get({ host: '127.0.0.1', port: PORT, path }, (r) => {
      let d = '';
      r.on('data', (c) => (d += c));
      r.on('end', () => {
        try { resolve(JSON.parse(d)); } catch (e) { reject(e); }
      });
    });
    req.on('error', reject);
  });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  let targets = null;
  for (let i = 0; i < 50; i++) {
    try { targets = await getJson('/json'); if (targets && targets.length) break; } catch (e) {}
    await sleep(400);
  }
  if (!targets || !targets.length) { console.error('CDP_UNAVAILABLE'); process.exit(2); }

  let page = targets.find((t) => t.type === 'page' && !t.url.startsWith('devtools'));
  let wsUrl = page ? page.webSocketDebuggerUrl : null;
  if (!wsUrl) {
    // 尝试新建一个 tab
    const created = await getJson('/json/new?' + encodeURIComponent(TARGET));
    wsUrl = created.webSocketDebuggerUrl;
  }

  const ws = new WebSocket(wsUrl);
  let id = 0;
  const pending = new Map();
  const send = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const myId = ++id;
      pending.set(myId, resolve);
      ws.send(JSON.stringify({ id: myId, method, params }));
      setTimeout(() => { if (pending.has(myId)) { pending.delete(myId); resolve(null); } }, 15000);
    });

  const events = [];
  const imageResponses = [];
  const failed = [];

  ws.onmessage = (ev) => {
    let msg; try { msg = JSON.parse(ev.data); } catch (e) { return; }
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg.result); pending.delete(msg.id); return; }
    if (msg.method === 'Runtime.exceptionThrown') {
      const d = msg.params.exceptionDetails;
      events.push('[EXC] ' + ((d.exception && (d.exception.description || d.exception.value)) || d.text));
    } else if (msg.method === 'Log.entryAdded') {
      events.push('[' + msg.params.entry.level + '] ' + msg.params.entry.text);
    } else if (msg.method === 'Network.responseReceived') {
      const r = msg.params.response; const u = msg.params.response.url;
      if (u && u.includes('/proxy') && (r.mimeType || '').startsWith('image')) {
        imageResponses.push({ url: u.slice(0, 80), status: r.status, type: r.mimeType });
      }
    } else if (msg.method === 'Network.requestFailed') {
      failed.push({ url: (msg.params.request && msg.params.request.url || '').slice(0, 80), err: msg.params.errorText });
    }
  };

  await new Promise((r) => (ws.onopen = r));
  await send('Runtime.enable');
  await send('Log.enable');
  await send('Page.enable');
  await send('Network.enable');
  // 测试播放必须静音：注入 video 自动静音（配合浏览器 --mute-audio 双保险）
  await send('Page.addScriptToEvaluateOnNewDocument', {
    source:
      "(function(){var p=HTMLMediaElement.prototype.play;HTMLMediaElement.prototype.play=function(){try{this.muted=true;this.volume=0;}catch(e){}return p.apply(this,arguments);};document.addEventListener('play',function(e){if(e.target&&e.target.tagName==='VIDEO'){try{e.target.muted=true;e.target.volume=0;}catch(x){}}},true);})();",
  });
  await send('Page.navigate', { url: TARGET });
  await sleep(WAIT_MS);

  if (CLICK_XF !== null && CLICK_YF !== null && !Number.isNaN(CLICK_XF) && !Number.isNaN(CLICK_YF)) {
    const m = await send('Runtime.evaluate', {
      expression: 'JSON.stringify({w:window.innerWidth,h:window.innerHeight,dpr:window.devicePixelRatio})',
      returnByValue: true,
    });
    let w = 1080, h = 600;
    try { const o = JSON.parse(m.result.value); w = o.w; h = o.h; } catch (e) {}
    const cx = Math.round(CLICK_XF * w);
    const cy = Math.round(CLICK_YF * h);
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: cx, y: cy, button: 'none' });
    await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: cx, y: cy, button: 'left', clickCount: 1 });
    await sleep(60);
    await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: cx, y: cy, button: 'left', clickCount: 1 });
    events.push('[CLICK] ' + cx + ',' + cy + ' (viewport ' + w + 'x' + h + ')');
    await sleep(WAIT_AFTER_CLICK);
  }

  let shotB64 = null;
  try {
    const sc = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
    shotB64 = sc && sc.data;
    if (shotB64) fs.writeFileSync(SHOT, Buffer.from(shotB64, 'base64'));
  } catch (e) { events.push('[SHOT_FAIL] ' + e.message); }

  const res = await send('Runtime.evaluate', { expression: EXPR, awaitPromise: true, returnByValue: true });
  const evalVal = (res && res.result && res.result.value !== undefined) ? res.result.value : JSON.stringify(res);

  console.log(JSON.stringify({
    title: evalVal,
    imageResponses: imageResponses.slice(0, 12),
    imageCount: imageResponses.length,
    failed: failed.slice(0, 12),
    failedCount: failed.length,
    events: events.slice(-30),
  }, null, 2));
  console.error('SCREENSHOT_SAVED=' + (fs.existsSync(SHOT) ? SHOT : 'NONE'));
  process.exit(0);
})();
