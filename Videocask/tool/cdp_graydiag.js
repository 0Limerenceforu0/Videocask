// Web 播放灰屏诊断：打开详情页 → 点播放 → 抓 video / flt-platform-view / MediaKit 内部状态。
// 用法：node tool/cdp_graydiag.js [outPng]
const http = require('http');
const fs = require('fs');
const PORT = 9222;
const URL = 'http://127.0.0.1:8787/#/detail?id=10548';
const OUT = process.argv[2] || 'tool/gray_diag.png';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const getJson = (path) =>
  new Promise((res, rej) => {
    http.get({ host: '127.0.0.1', port: PORT, path }, (r) => {
      let d = '';
      r.on('data', (c) => (d += c));
      r.on('end', () => {
        try {
          res(JSON.parse(d));
        } catch (e) {
          rej(e);
        }
      });
    }).on('error', rej);
  });

// 深度探测：video 元素、platform-view、MediaKit JS 对象、video 元素在 DOM 里的位置与尺寸
const PROBE = `(() => {
  const out = {};
  const vs = [...document.querySelectorAll('video')];
  out.videoCount = vs.length;
  out.videos = vs.map(v => {
    const r = v.getBoundingClientRect();
    const cs = getComputedStyle(v);
    return {
      src: (v.currentSrc || v.src || '').slice(0, 120),
      ct: +v.currentTime.toFixed(2), dur: +(v.duration || 0).toFixed(2),
      paused: v.paused, rs: v.readyState, ns: v.networkState,
      vw: v.videoWidth, vh: v.videoHeight,
      err: v.error ? {code: v.error.code, msg: v.error.message} : null,
      rect: [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)],
      display: cs.display, visibility: cs.visibility, opacity: cs.opacity,
      zIndex: cs.zIndex, objectFit: cs.objectFit,
      parent: v.parentElement ? v.parentElement.tagName + '.' + (v.parentElement.className||'').slice(0,60) : null,
    };
  });
  const pvs = [...document.querySelectorAll('flt-platform-view, flt-platform-view-slot')];
  out.pvCount = pvs.length;
  out.pvs = pvs.map(e => {
    const r = e.getBoundingClientRect();
    const cs = getComputedStyle(e);
    return { tag: e.tagName, rect: [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)],
             display: cs.display, visibility: cs.visibility, opacity: cs.opacity, slot: e.getAttribute('slot') };
  });
  const canvases = [...document.querySelectorAll('canvas')];
  out.canvasCount = canvases.length;
  out.canvases = canvases.map(c => { const r = c.getBoundingClientRect();
    return {rect:[Math.round(r.x),Math.round(r.y),Math.round(r.width),Math.round(r.height)], w:c.width, h:c.height}; });
  out.mk = null;
  return out;
})()`;

(async () => {
  let targets;
  try {
    targets = await getJson('/json');
  } catch (e) {
    console.log('9222 unreachable:', e.message);
    process.exit(1);
  }
  const target =
    targets.find((t) => t.type === 'page' && /8787/.test(t.url)) ||
    targets.find((t) => t.type === 'page');
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  let id = 0;
  const pending = new Map();
  const send = (method, params = {}) =>
    new Promise((resolve) => {
      const myId = ++id;
      pending.set(myId, resolve);
      ws.send(JSON.stringify({ id: myId, method, params }));
      setTimeout(() => {
        if (pending.has(myId)) {
          pending.delete(myId);
          resolve(null);
        }
      }, 20000);
    });
  ws.onmessage = (ev) => {
    let m;
    try {
      m = JSON.parse(ev.data);
    } catch (e) {
      return;
    }
    if (m.id && pending.has(m.id)) {
      pending.get(m.id)(m.result);
      pending.delete(m.id);
    }
  };
  ws.onopen = async () => {
    await send('Runtime.enable');
    await send('Page.enable');
    await send('Log.enable');
    // 静音保险
    await send('Page.addScriptToEvaluateOnNewDocument', {
      source:
        "(function(){var p=HTMLMediaElement.prototype.play;HTMLMediaElement.prototype.play=function(){try{this.muted=true;this.volume=0;}catch(e){}return p.apply(this,arguments);};document.addEventListener('play',function(e){if(e.target&&e.target.tagName==='VIDEO'){try{e.target.muted=true;e.target.volume=0;}catch(x){}}},true);var _ce=document.createElement.bind(document);document.createElement=function(t){var el=_ce(t);if(String(t).toLowerCase()==='video'){try{el.muted=true;el.volume=0;}catch(e){}}return el;};})();",
    });

    console.log('navigate clean...');
    await send('Page.navigate', { url: 'about:blank' });
    await sleep(1200);
    await send('Page.navigate', { url: URL });
    await sleep(22000);

    // 点中间大播放按钮
    const m = await send('Runtime.evaluate', {
      expression: 'JSON.stringify({w:innerWidth,h:innerHeight})',
      returnByValue: true,
    });
    let w = 1342,
      h = 669;
    try {
      const o = JSON.parse(m.result.value);
      w = o.w;
      h = o.h;
    } catch (e) {}
    const cx = Math.round(0.375 * w),
      cy = Math.round(0.366 * h);
    console.log('click play area', cx, cy, 'vp', w, h);
    for (const t of ['mouseMoved', 'mousePressed']) {
      await send('Input.dispatchMouseEvent', { type: t, x: cx, y: cy, button: t === 'mouseMoved' ? 'none' : 'left', clickCount: 1 });
      await sleep(50);
    }
    await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: cx, y: cy, button: 'left', clickCount: 1 });

    for (const wait of [6000, 12000, 12000]) {
      await sleep(wait);
      const st = await send('Runtime.evaluate', { expression: PROBE, returnByValue: true });
      console.log('--- PROBE ---');
      console.log(JSON.stringify(st && st.result && st.result.value, null, 1));
      await send('Runtime.evaluate', {
        expression:
          'document.querySelectorAll("video").forEach(function(v){try{v.muted=true;v.volume=0;}catch(e){}});"muted"',
        returnByValue: true,
      });
    }

    const shot = await send('Page.captureScreenshot', { format: 'png' });
    if (shot && shot.data) {
      fs.writeFileSync(OUT, Buffer.from(shot.data, 'base64'));
      console.log('SHOT saved', OUT);
    }
    ws.close();
    process.exit(0);
  };
  setTimeout(() => {
    console.log('timeout');
    process.exit(0);
  }, 120000);
})();
