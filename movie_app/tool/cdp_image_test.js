// 在真实浏览器引擎（Edge/Chromium）里测试图片能否加载 + 是否带 CORS 头。
// 用法：node tool/cdp_image_test.js <imageUrl>
// 前置：Edge 以 --remote-debugging-port=9222 启动
const http = require('http');

const URL_TO_TEST =
  process.argv[2] ||
  'https://img.feifeiimg.vip/upload/vod/20221111-1/95bc5e95ce36468bcf4a010492123915.jpg';
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
    }
  };

  await new Promise((r) => (ws.onopen = r));
  await send('Runtime.enable');

  const expr = `(async () => {
    const url = ${JSON.stringify(URL_TO_TEST)};
    const out = {};
    const t0 = Date.now();
    try {
      const r = await fetch(url, { mode: 'cors', cache: 'no-store' });
      const b = await r.blob();
      out.corsFetch = {
        status: r.status,
        type: r.type,
        contentType: r.headers.get('content-type'),
        bytes: b.size,
        ms: Date.now() - t0,
      };
    } catch (e) {
      out.corsFetch = { error: e.name + ': ' + e.message, ms: Date.now() - t0 };
    }
    try {
      out.noCorsImg = await new Promise((res) => {
        const im = new Image();
        const timer = setTimeout(() => res({ error: 'timeout' }), 15000);
        im.onload = () => { clearTimeout(timer); res({ w: im.naturalWidth, h: im.naturalHeight }); };
        im.onerror = () => { clearTimeout(timer); res({ error: 'onerror' }); };
        im.src = url;
      });
    } catch (e) {
      out.noCorsImg = { error: String(e) };
    }
    return JSON.stringify(out);
  })()`;

  const res = await send('Runtime.evaluate', {
    expression: expr,
    awaitPromise: true,
    returnByValue: true,
  });
  console.log('IMAGE_TEST_RESULT:');
  console.log(
    (res && res.result && res.result.value) || JSON.stringify(res),
  );
  process.exit(0);
})();
