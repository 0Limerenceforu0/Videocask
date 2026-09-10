// 通过 CDP 连接已有的 page target，暂停并静音其中播放的 <video>，并截图留证。
// 用法：node tool/cdp_pause.js
const http = require('http');
const fs = require('fs');
const PORT = 9222;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const getJson = path => new Promise((res, rej) => {
  http.get({ host: '127.0.0.1', port: PORT, path }, r => {
    let d = ''; r.on('data', c => d += c);
    r.on('end', () => { try { res(JSON.parse(d)); } catch (e) { rej(e); } });
  }).on('error', rej);
});

(async () => {
  let targets;
  try { targets = await getJson('/json'); }
  catch (e) { console.log('9222 unreachable:', e.message); process.exit(1); }
  const target = targets.find(t => t.type === 'page' && /8787|detail/.test(t.url))
             || targets.find(t => t.type === 'page');
  if (!target) { console.log('no page target'); process.exit(1); }
  console.log('TARGET', target.url);

  const ws = new WebSocket(target.webSocketDebuggerUrl);
  let id = 0;
  let step = 'init';

  ws.onopen = async () => {
    ws.send(JSON.stringify({ id: ++id, method: 'Runtime.enable' }));
    await sleep(150);
    ws.send(JSON.stringify({ id: ++id, method: 'Page.enable' }));
    await sleep(150);
    step = 'pause';
    ws.send(JSON.stringify({
      id: ++id, method: 'Runtime.evaluate',
      params: {
        expression: "(function(){var vs=document.querySelectorAll('video');vs.forEach(function(v){try{v.pause();v.muted=true;}catch(e){}});var v0=vs[0];return {count:vs.length, ct:v0?+v0.currentTime.toFixed(2):null, paused:v0? v0.paused:null, muted:v0? v0.muted:null};})()",
        returnByValue: true
      }
    }));
  };

  ws.onmessage = (ev) => {
    let msg; try { msg = JSON.parse(ev.data); } catch (e) { return; }
    if (msg.id && step === 'pause') {
      console.log('PAUSE_RESULT', JSON.stringify(msg.result && msg.result.result && msg.result.result.value));
      step = 'shot';
      ws.send(JSON.stringify({ id: ++id, method: 'Page.captureScreenshot', params: { format: 'png' } }));
    } else if (msg.id && step === 'shot') {
      if (msg.result && msg.result.data) {
        fs.writeFileSync('tool/paused.png', Buffer.from(msg.result.data, 'base64'));
        console.log('SHOT saved tool/paused.png');
      }
      ws.close();
      process.exit(0);
    }
  };

  setTimeout(() => { console.log('timeout'); process.exit(0); }, 8000);
})();
