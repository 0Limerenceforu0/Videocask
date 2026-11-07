// Web 播放流程逐步探针：首页 → 详情页 → 点播放，每步截图 + 回读状态。
// 用法：node tool/cdp_playflow.js
const http = require('http');
const fs = require('fs');
const PORT = 9222;
const BASE = 'http://127.0.0.1:8787';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const getJson = (p) =>
  new Promise((res, rej) => {
    http.get({ host: '127.0.0.1', port: PORT, path: p }, (r) => {
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

const STATE = `(() => {
  const vs=[...document.querySelectorAll('video')];
  const gp=document.querySelector('flt-glass-pane');
  const cv=gp&&gp.shadowRoot?gp.shadowRoot.querySelector('canvas'):null;
  return {
    url: location.hash,
    videoCount: vs.length,
    videos: vs.map(v=>({src:(v.currentSrc||v.src||'').slice(0,100), ct:+v.currentTime.toFixed(2),
      dur:+(v.duration||0).toFixed(2), paused:v.paused, rs:v.readyState, vw:v.videoWidth, vh:v.videoHeight,
      err:v.error?v.error.code:null})),
    pvCount: document.querySelectorAll('flt-platform-view').length,
    canvas: cv ? [cv.width, cv.height] : null,
    splash: !!document.getElementById('flutter-splash'),
  };
})()`;

(async () => {
  const targets = await getJson('/json');
  const page =
    targets.find((t) => t.type === 'page' && /8787/.test(t.url)) ||
    targets.find((t) => t.type === 'page');
  if (!page) {
    console.log('no page');
    process.exit(1);
  }
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  let id = 0;
  const pend = new Map();
  const send = (m, p = {}) =>
    new Promise((r) => {
      const i = ++id;
      pend.set(i, r);
      ws.send(JSON.stringify({ id: i, method: m, params: p }));
      setTimeout(() => {
        if (pend.has(i)) {
          pend.delete(i);
          r(null);
        }
      }, 25000);
    });
  ws.onmessage = (e) => {
    let m;
    try {
      m = JSON.parse(e.data);
    } catch (x) {
      return;
    }
    if (m.id && pend.has(m.id)) {
      pend.get(m.id)(m.result);
      pend.delete(m.id);
    }
  };

  const shot = async (name) => {
    const s = await send('Page.captureScreenshot', { format: 'png', fromSurface: true });
    if (s && s.data) {
      fs.writeFileSync(`tool/${name}.png`, Buffer.from(s.data, 'base64'));
      console.log(`  [shot] tool/${name}.png`);
    }
  };
  const probe = async (label) => {
    const st = await send('Runtime.evaluate', { expression: STATE, returnByValue: true });
    console.log(`  [${label}]`, JSON.stringify(st && st.result && st.result.value));
  };
  const click = async (xf, yf) => {
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
    const x = Math.round(xf * w),
      y = Math.round(yf * h);
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y, button: 'none' });
    await sleep(80);
    await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
    await sleep(70);
    await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
    console.log(`  [click] ${xf},${yf} -> ${x},${y} (vp ${w}x${h})`);
  };

  ws.onopen = async () => {
    await send('Page.enable');
    await send('Runtime.enable');
    await send('Log.enable');
    // 静音双保险（用户硬性要求：测试播放绝不出声）
    await send('Page.addScriptToEvaluateOnNewDocument', {
      source:
        "(function(){var p=HTMLMediaElement.prototype.play;HTMLMediaElement.prototype.play=function(){try{this.muted=true;this.volume=0;}catch(e){}return p.apply(this,arguments);};document.addEventListener('play',function(e){if(e.target&&e.target.tagName==='VIDEO'){try{e.target.muted=true;e.target.volume=0;}catch(x){}}},true);var _c=document.createElement.bind(document);document.createElement=function(t){var el=_c(t);if(String(t).toLowerCase()==='video'){try{el.muted=true;el.volume=0;}catch(e){}}return el;};})();",
    });

    console.log('STEP 1: 载入首页');
    await send('Page.navigate', { url: BASE + '/' });
    await sleep(14000);
    await probe('home');
    await shot('flow_1_home');

    console.log('STEP 2: 进详情页 10548');
    await send('Page.navigate', { url: BASE + '/#/detail?id=10548' });
    await sleep(1000);
    // hash 路由不触发重载，用 hashchange 或直接重载
    await send('Page.reload', { ignoreCache: false });
    await sleep(16000);
    await probe('detail');
    await shot('flow_2_detail');

    console.log('STEP 3: 点播放器区域');
    for (const [xf, yf] of [
      [0.375, 0.36],
      [0.375, 0.45],
      [0.5, 0.5],
    ]) {
      await click(xf, yf);
      await sleep(9000);
      await probe(`after-click-${xf}`);
      const st = await send('Runtime.evaluate', { expression: STATE, returnByValue: true });
      const v = st && st.result && st.result.value;
      if (v && (v.videoCount > 0 || v.pvCount > 0 || (v.url || '').includes('player'))) {
        console.log('  >>> 播放器已挂载，深入观察');
        await sleep(12000);
        await probe('playing');
        await shot('flow_3_player');
        break;
      }
    }
    await probe('final');
    await shot('flow_4_final');
    ws.close();
    process.exit(0);
  };
  setTimeout(() => {
    console.log('timeout');
    process.exit(0);
  }, 180000);
})();
