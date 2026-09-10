// 在当前页面按视口比例点击，等待后回读 video 状态并截图。
// 用法：node tool/cdp_tap.js <xf> <yf> [waitAfterMs] [outPng]
const http = require('http');
const fs = require('fs');
const PORT = 9222;
const XF = parseFloat(process.argv[2] || '0.376');
const YF = parseFloat(process.argv[3] || '0.378');
const WAIT = parseInt(process.argv[4] || '12000', 10);
const OUT = process.argv[5] || 'tool/tap.png';
const sleep = ms => new Promise(r => setTimeout(r, ms));
const getJson = path => new Promise((res, rej) => {
  http.get({ host: '127.0.0.1', port: PORT, path }, r => {
    let d = ''; r.on('data', c => d += c);
    r.on('end', () => { try { res(JSON.parse(d)); } catch (e) { rej(e); } });
  }).on('error', rej);
});
const STATE = '(()=>{const v=document.querySelector("video");const pvs=[...document.querySelectorAll("flt-platform-view")].map(e=>{const r=e.getBoundingClientRect();return [Math.round(r.x),Math.round(r.y),Math.round(r.width),Math.round(r.height)];});const vr=v?v.getBoundingClientRect():null;return {video:v?{ct:+v.currentTime.toFixed(2),paused:v.paused,rs:v.readyState,vw:v.videoWidth,vh:v.videoHeight,rect:vr?[Math.round(vr.x),Math.round(vr.y),Math.round(vr.width),Math.round(vr.height)]:null}:null,pvRects:pvs};})()';

(async () => {
  const targets = await getJson('/json');
  const target = targets.find(t => t.type === 'page' && /8787/.test(t.url)) || targets.find(t => t.type === 'page');
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  let id = 0; const pending = new Map();
  const send = (method, params = {}) => new Promise(res => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); setTimeout(() => { if (pending.has(i)) { pending.delete(i); res(null); } }, 15000); });
  ws.onmessage = ev => { let m; try { m = JSON.parse(ev.data); } catch (e) { return; } if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); } };
  ws.onopen = async () => {
    await send('Runtime.enable'); await send('Page.enable');
    // 测试播放必须静音：注入 video 自动静音（配合浏览器 --mute-audio 双保险）
    await send('Page.addScriptToEvaluateOnNewDocument', {
      source: "(function(){var p=HTMLMediaElement.prototype.play;HTMLMediaElement.prototype.play=function(){try{this.muted=true;this.volume=0;}catch(e){}return p.apply(this,arguments);};document.addEventListener('play',function(e){if(e.target&&e.target.tagName==='VIDEO'){try{e.target.muted=true;e.target.volume=0;}catch(x){}}},true);})();",
    });
    const m = await send('Runtime.evaluate', { expression: 'JSON.stringify({w:innerWidth,h:innerHeight})', returnByValue: true });
    let w = 1342, h = 761; try { const o = JSON.parse(m.result.value); w = o.w; h = o.h; } catch (e) {}
    const cx = Math.round(XF * w), cy = Math.round(YF * h);
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: cx, y: cy, button: 'none' });
    await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: cx, y: cy, button: 'left', clickCount: 1 });
    await sleep(60);
    await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: cx, y: cy, button: 'left', clickCount: 1 });
    // 立即静音（点击可能触发播放）
    await send('Runtime.evaluate', { expression: 'document.querySelectorAll("video").forEach(function(v){try{v.muted=true;v.volume=0;}catch(e){}})' });
    console.log('clicked', cx, cy, 'of', w, h);
    await sleep(WAIT);
    const st = await send('Runtime.evaluate', { expression: STATE, returnByValue: true });
    console.log('STATE:', JSON.stringify(st && st.result && st.result.value));
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    if (shot && shot.data) { fs.writeFileSync(OUT, Buffer.from(shot.data, 'base64')); console.log('SHOT', OUT); }
    ws.close(); process.exit(0);
  };
  setTimeout(() => process.exit(0), 40000);
})();
