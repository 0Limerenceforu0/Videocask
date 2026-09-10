// 在当前 page target 上直接 play 现有 <video>，等待后回读状态 + platform view 尺寸 + 截图。
// 用法：node tool/cdp_play.js [outPng]
const http = require('http');
const fs = require('fs');
const PORT = 9222;
const OUT = process.argv[2] || 'tool/play.png';
const sleep = ms => new Promise(r => setTimeout(r, ms));
const getJson = path => new Promise((res, rej) => {
  http.get({ host: '127.0.0.1', port: PORT, path }, r => {
    let d = ''; r.on('data', c => d += c);
    r.on('end', () => { try { res(JSON.parse(d)); } catch (e) { rej(e); } });
  }).on('error', rej);
});

const STATE = '(()=>{const v=document.querySelector("video");const pv=document.querySelector("flt-platform-view");const pr=pv?pv.getBoundingClientRect():null;const vr=v?v.getBoundingClientRect():null;return {video:v?{ct:+v.currentTime.toFixed(2),paused:v.paused,rs:v.readyState,vw:v.videoWidth,vh:v.videoHeight,err:v.error?v.error.code:null,rect:vr?[Math.round(vr.x),Math.round(vr.y),Math.round(vr.width),Math.round(vr.height)]:null}:null,pvRect:pr?[Math.round(pr.x),Math.round(pr.y),Math.round(pr.width),Math.round(pr.height)]:null};})()';

(async () => {
  let targets;
  try { targets = await getJson('/json'); } catch (e) { console.log('9222 unreachable:', e.message); process.exit(1); }
  const target = targets.find(t => t.type === 'page' && /8787/.test(t.url)) || targets.find(t => t.type === 'page');
  if (!target) { console.log('no page target'); process.exit(1); }
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  let id = 0;
  const want = {};
  ws.onopen = async () => {
    ws.send(JSON.stringify({ id: ++id, method: 'Runtime.enable' }));
    await sleep(150);
    ws.send(JSON.stringify({ id: ++id, method: 'Page.enable' }));
    await sleep(150);
    // 1) play
    want.play = ++id;
    // 测试播放必须静音：muted=true 后再 play
    ws.send(JSON.stringify({ id: want.play, method: 'Runtime.evaluate', params: { expression: '(v=>{v.muted=true;v.volume=0;v.play();return {ct:+v.currentTime.toFixed(2),paused:v.paused,muted:v.muted};})(document.querySelector("video"))', returnByValue: true } }));
  };
  ws.onmessage = async ev => {
    let m; try { m = JSON.parse(ev.data); } catch (e) { return; }
    if (m.id === want.play) {
      console.log('PLAY:', JSON.stringify(m.result && m.result.result && m.result.result.value));
      await sleep(6000);
      want.state = ++id;
      ws.send(JSON.stringify({ id: want.state, method: 'Runtime.evaluate', params: { expression: STATE, returnByValue: true } }));
    } else if (m.id === want.state) {
      console.log('STATE:', JSON.stringify(m.result && m.result.result && m.result.result.value));
      want.shot = ++id;
      ws.send(JSON.stringify({ id: want.shot, method: 'Page.captureScreenshot', params: { format: 'png' } }));
    } else if (m.id === want.shot) {
      if (m.result && m.result.data) { fs.writeFileSync(OUT, Buffer.from(m.result.data, 'base64')); console.log('SHOT saved', OUT); }
      ws.close(); process.exit(0);
    }
  };
  setTimeout(() => { console.log('timeout'); process.exit(0); }, 15000);
})();
