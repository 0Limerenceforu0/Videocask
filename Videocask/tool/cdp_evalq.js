// 在已打开的 page target 上执行 JS 求值（不导航）。用法：node tool/cdp_evalq.js "<jsExpr>"
const http = require('http');
const PORT = 9222;
const EXPR = process.argv[2] || 'document.title';
const sleep = ms => new Promise(r => setTimeout(r, ms));
const getJson = path => new Promise((res, rej) => {
  http.get({ host: '127.0.0.1', port: PORT, path }, r => {
    let d = ''; r.on('data', c => d += c);
    r.on('end', () => { try { res(JSON.parse(d)); } catch (e) { rej(e); } });
  }).on('error', rej);
});

(async () => {
  let targets;
  try { targets = await getJson('/json'); } catch (e) { console.log('9222 unreachable:', e.message); process.exit(1); }
  const target = targets.find(t => t.type === 'page' && /8787/.test(t.url)) || targets.find(t => t.type === 'page');
  if (!target) { console.log('no page target'); process.exit(1); }
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  let id = 0, step = 'init';
  ws.onopen = async () => {
    ws.send(JSON.stringify({ id: ++id, method: 'Runtime.enable' }));
    await sleep(150);
    step = 'eval';
    ws.send(JSON.stringify({ id: ++id, method: 'Runtime.evaluate', params: { expression: EXPR, returnByValue: true } }));
  };
  ws.onmessage = ev => {
    let m; try { m = JSON.parse(ev.data); } catch (e) { return; }
    if (m.id && step === 'eval') {
      const r = m.result && m.result.result;
      console.log(r && r.exceptionDetails ? 'EXCEPTION: ' + JSON.stringify(r.exceptionDetails) : JSON.stringify(r && r.value, null, 2));
      ws.close(); process.exit(0);
    }
  };
  setTimeout(() => { console.log('timeout'); process.exit(0); }, 6000);
})();
