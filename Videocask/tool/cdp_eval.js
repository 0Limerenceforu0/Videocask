// 通用 CDP 求值：打开页面 → 等待 → 在页面里执行 JS → 打印结果。
// 用法：node tool/cdp_eval.js <url> <waitMs> "<jsExpression>"
// 前置：Edge 以 --remote-debugging-port=9222 启动
const http = require('http');

const TARGET = process.argv[2] || 'about:blank';
const WAIT_MS = parseInt(process.argv[3] || '12000', 10);
const EXPR = process.argv[4] || 'document.title';
const PORT = 9222;

const getJson = (path) =>
  new Promise((resolve, reject) => {
    const req = http.get({ host: '127.0.0.1', port: PORT, path }, (r) => {
      let d = '';
      r.on('data', (c) => (d += c));
      r.on('end', () => {
        try {
          resolve(JSON.parse(d));
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on('error', reject);
  });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  let targets = null;
  for (let i = 0; i < 40; i++) {
    try {
      targets = await getJson('/json');
      if (targets && targets.length) break;
    } catch (e) {}
    await sleep(500);
  }
  if (!targets || !targets.length) {
    console.error('CDP_UNAVAILABLE');
    process.exit(2);
  }
  const page = targets.find((t) => t.type === 'page') || targets[0];
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  let id = 0;
  const pending = new Map();
  const events = [];
  const send = (method, params = {}) =>
    new Promise((resolve) => {
      const myId = ++id;
      pending.set(myId, resolve);
      ws.send(JSON.stringify({ id: myId, method, params }));
    });

  ws.onmessage = (ev) => {
    let msg;
    try {
      msg = JSON.parse(ev.data);
    } catch (e) {
      return;
    }
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg.result);
      pending.delete(msg.id);
      return;
    }
    if (msg.method === 'Runtime.exceptionThrown') {
      const d = msg.params.exceptionDetails;
      events.push(
        '[EXC] ' +
          ((d.exception && (d.exception.description || d.exception.value)) ||
            d.text),
      );
    }
    if (msg.method === 'Log.entryAdded') {
      events.push('[' + msg.params.entry.level + '] ' + msg.params.entry.text);
    }
  };

  await new Promise((r) => (ws.onopen = r));
  await send('Runtime.enable');
  await send('Log.enable');
  await send('Page.enable');
  await send('Network.enable');
  await send('Page.navigate', { url: TARGET });
  await sleep(WAIT_MS);

  const res = await send('Runtime.evaluate', {
    expression: EXPR,
    awaitPromise: true,
    returnByValue: true,
  });
  console.log('===== EVAL RESULT =====');
  console.log(
    (res && res.result && res.result.value !== undefined
      ? res.result.value
      : JSON.stringify(res)),
  );
  if (events.length) {
    console.log('===== PAGE EVENTS =====');
    console.log(events.slice(-40).join('\n'));
  }
  process.exit(0);
})();
