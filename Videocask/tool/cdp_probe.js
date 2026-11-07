// 通过 Chrome DevTools Protocol 抓取网页端控制台日志与异常。
// 用法：node tool/cdp_probe.js [目标URL] [等待毫秒]
// 前置：已用 --remote-debugging-port=9222 启动 Edge/Chrome
const http = require('http');

const TARGET = process.argv[2] || 'http://127.0.0.1:8787';
const WAIT_MS = parseInt(process.argv[3] || '30000', 10);
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
    } catch (e) {
      /* 还没起来 */
    }
    await sleep(500);
  }
  if (!targets || !targets.length) {
    console.error('CDP_UNAVAILABLE: 无法连接 127.0.0.1:' + PORT);
    process.exit(2);
  }

  const page = targets.find((t) => t.type === 'page') || targets[0];
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  const logs = [];
  let id = 0;
  const send = (method, params = {}) =>
    ws.send(JSON.stringify({ id: ++id, method, params }));

  ws.onopen = () => {
    send('Runtime.enable');
    send('Log.enable');
    send('Page.enable');
    send('Network.enable');
    send('Network.setCacheDisabled', { cacheDisabled: true });
    send('Page.navigate', { url: TARGET });
  };

  const reqs = new Map();
  const allReqs = new Map();

  ws.onmessage = (ev) => {
    let msg;
    try {
      msg = JSON.parse(ev.data);
    } catch (e) {
      return;
    }
    if (msg.method === 'Runtime.consoleAPICalled') {
      const text = (msg.params.args || [])
        .map((a) =>
          a.value !== undefined
            ? a.value
            : a.description !== undefined
              ? a.description
              : a.type,
        )
        .join(' ');
      logs.push('[' + msg.params.type + '] ' + text);
    } else if (msg.method === 'Runtime.exceptionThrown') {
      const d = msg.params.exceptionDetails;
      const desc =
        (d.exception && (d.exception.description || d.exception.value)) ||
        d.text;
      logs.push('[EXCEPTION] ' + desc);
    } else if (msg.method === 'Log.entryAdded') {
      logs.push('[' + msg.params.entry.level + '] ' + msg.params.entry.text);
    } else if (msg.method === 'Network.requestWillBeSent') {
      const u = msg.params.request.url;
      allReqs.set(msg.params.requestId, u);
      if (u.includes('/proxy') || u.includes('/hls') || u.startsWith(TARGET)) {
        reqs.set(msg.params.requestId, u);
      }
    } else if (msg.method === 'Network.responseReceived') {
      if (reqs.has(msg.params.requestId)) {
        logs.push(
          '[NET ' +
            msg.params.response.status +
            '] ' +
            reqs.get(msg.params.requestId).slice(0, 130),
        );
        reqs.delete(msg.params.requestId);
      }
    } else if (msg.method === 'Network.loadingFailed') {
      const u = allReqs.get(msg.params.requestId) || '(unknown)';
      const t = msg.params.type || '?';
      logs.push(
        '[FAIL ' + t + ': ' + msg.params.errorText + '] ' + u.slice(0, 150),
      );
    }
  };

  await sleep(WAIT_MS);
  console.log('===== CDP LOGS =====');
  console.log(logs.join('\n'));
  console.log('===== END =====');
  process.exit(0);
})();
