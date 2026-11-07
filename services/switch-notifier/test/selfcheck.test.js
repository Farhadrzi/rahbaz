'use strict';

// Self-check: feeds sample log lines through the detector, then runs the whole
// service (tailer -> hub -> JSONL / SSE / HTTP) against a temp dir. No Docker needed.
//   npm test

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');

const { detectLine } = require('../src/detector');
const { createApp } = require('../src/app');

const quiet = { warn() {}, log() {}, error() {} };

/* ---------------------------------------------------------------- detector */

const POSITIVE = [
  {
    name: 'gin 429 access line',
    line: '[GIN] 2026/01/01 - 12:00:00 | 429 | 1.2s | 127.0.0.1 | POST "/v1/messages"',
    type: 'switch.quota',
    reasonIncludes: 'http 429',
  },
  {
    name: 'logrus 429 with provider + failing auth',
    line: 'time="2026-01-01T12:00:00Z" level=warn msg="upstream 429 Too Many Requests for claude auth claude-a@example.com, cooling down"',
    type: 'switch.quota',
    provider: 'claude',
    from: 'claude-a@example.com',
  },
  {
    name: 'explicit switch with from/to after quota',
    line: '[warn] switching from auth claude-a@example.com to claude-b@example.com after quota exceeded',
    type: 'switch.quota',
    provider: 'claude',
    from: 'claude-a@example.com',
    to: 'claude-b@example.com',
  },
  {
    name: 'json 401 refresh failure',
    line: '{"level":"warn","msg":"token refresh failed","provider":"codex","auth_id":"codex-1","status":401}',
    type: 'switch.auth',
    provider: 'codex',
    from: 'codex-1',
  },
  {
    name: 'plain unauthorized text',
    line: '[error] antigravity request failed: Unauthorized (invalid_grant)',
    type: 'switch.auth',
    provider: 'antigravity',
  },
  {
    name: '503 overloaded',
    line: 'time="2026-01-01T12:00:00Z" level=error msg="upstream returned 503 overloaded_error" provider=anthropic',
    type: 'switch.error',
    provider: 'claude',
  },
  {
    name: 'connection reset',
    line: '[error] codex stream error: read tcp 10.0.0.2:5555: connection reset by peer',
    type: 'switch.error',
    provider: 'codex',
  },
  {
    name: 'bare failover wording',
    line: '[info] failover from codex-a to codex-b',
    type: 'switch.unknown',
    provider: 'codex',
    from: 'codex-a',
    to: 'codex-b',
  },
  {
    name: 'cooldown only',
    line: 'level=info msg="auth gemini-a is cooling down for 30m"',
    type: 'switch.unknown',
    provider: 'gemini',
    from: 'gemini-a',
  },
];

for (const c of POSITIVE) {
  test(`detector: ${c.name}`, () => {
    const ev = detectLine(c.line, { source: 'main.log' });
    assert.ok(ev, 'expected an event');
    assert.equal(ev.type, c.type);
    assert.ok(ev.reason && ev.reason.length > 0, 'reason must be set');
    assert.ok(!Number.isNaN(Date.parse(ev.ts)), 'ts must be ISO');
    assert.equal(ev.source, 'main.log');
    if (c.provider) assert.equal(ev.provider, c.provider);
    if (c.from) assert.equal(ev.from, c.from);
    if (c.to) assert.equal(ev.to, c.to);
    if (c.reasonIncludes) assert.ok(ev.reason.includes(c.reasonIncludes), ev.reason);
  });
}

test('detector: ignores ordinary traffic and noise', () => {
  const quietLines = [
    '[GIN] 2026/01/01 - 12:00:00 | 200 | 1.2s | 127.0.0.1 | POST "/v1/messages"',
    'time="2026-01-01T12:00:00Z" level=info msg="server started on :8317"',
    'HTTP/1.1 101 Switching Protocols',
    '[GIN] 2026/01/01 - 12:00:00 | 200 | 429ms | 127.0.0.1 | GET "/v1/models"',
    '',
  ];
  for (const line of quietLines) assert.equal(detectLine(line), null, line);
});

test('detector: debug lines are skipped unless includeDebug', () => {
  const line = 'time="x" level=debug msg="request body: please explain HTTP 429 quota errors"';
  assert.equal(detectLine(line), null);
  assert.equal(detectLine(line, { includeDebug: true })?.type, 'switch.quota');
});

test('detector: secrets are redacted from raw', () => {
  const ev = detectLine(
    'level=warn msg="429 rate limit" Authorization: Bearer abcdef123456 api_key=sk-secretsecret1234 token="hunter2hunter2"',
  );
  assert.ok(ev);
  assert.ok(!/abcdef123456|secretsecret|hunter2/.test(ev.raw), ev.raw);
});

test('detector: very long lines are bounded', () => {
  const ev = detectLine(`level=warn status=429 ${'x'.repeat(50000)}`);
  assert.ok(ev);
  assert.ok(ev.raw.length <= 500);
});

/* --------------------------------------------------------------- end to end */

function get(port, p) {
  return new Promise((resolve, reject) => {
    http
      .get({ host: '127.0.0.1', port, path: p }, (res) => {
        let body = '';
        res.on('data', (d) => (body += d));
        res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body }));
      })
      .on('error', reject);
  });
}

function until(fn, ms = 5000) {
  const start = Date.now();
  return new Promise((resolve, reject) => {
    (function tick() {
      const v = fn();
      if (v) return resolve(v);
      if (Date.now() - start > ms) return reject(new Error('timeout waiting for condition'));
      setTimeout(tick, 25);
    })();
  });
}

test('service: tails a late-created log, serves SSE/status, appends JSONL', async (t) => {
  const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'rahbaz-sn-'));
  const logDir = path.join(tmp, 'logs'); // does not exist yet -> service must create it
  const switchLog = path.join(tmp, 'out', 'switches.jsonl');
  const app = createApp(
    { logDir, switchLog, port: 0, host: '127.0.0.1', pollMs: 50, dedupeMs: 0, replay: false, includeDebug: false, corsOrigin: '', proxyUrl: 'http://cliproxy:8317' },
    quiet,
  );
  const port = await app.start();
  t.after(async () => {
    await app.stop();
    await fsp.rm(tmp, { recursive: true, force: true });
  });

  // health + empty status before the proxy has written anything
  assert.deepEqual(JSON.parse((await get(port, '/health')).body), { ok: true });
  let status = JSON.parse((await get(port, '/status')).body);
  assert.equal(status.switches, 0);
  assert.equal(status.lastSwitch, null);
  assert.equal((await get(port, '/nope')).status, 404);
  assert.ok(fs.existsSync(logDir), 'log dir should be created when missing');

  // open the SSE stream and wait for the handshake
  let sseBuf = '';
  const sseReq = http.get({ host: '127.0.0.1', port, path: '/events' });
  const sseRes = await new Promise((resolve) => sseReq.on('response', resolve));
  assert.match(sseRes.headers['content-type'], /text\/event-stream/);
  sseRes.setEncoding('utf8');
  sseRes.on('data', (d) => (sseBuf += d));
  await until(() => sseBuf.includes(': connected'));

  // the proxy starts writing (file appears after startup, last line is partial)
  const file = path.join(logDir, 'main.log');
  await fsp.appendFile(file, '[GIN] 2026/01/01 - 12:00:00 | 200 | 5ms | 127.0.0.1 | GET "/v1/models"\n');
  await fsp.appendFile(file, 'level=warn msg="claude auth a@x.com hit 429 rate limit; switching from a@x.com to b@x.com"\n');
  await fsp.appendFile(file, 'level=error msg="codex 401 unauth'); // partial line
  await until(() => sseBuf.includes('"type":"switch.quota"'));
  await fsp.appendFile(file, 'orized"\n'); // completes the partial line
  await until(() => sseBuf.includes('"type":"switch.auth"'));

  const dataLines = sseBuf.split('\n').filter((l) => l.startsWith('data: ')).map((l) => JSON.parse(l.slice(6)));
  assert.equal(dataLines.length, 2);
  assert.equal(dataLines[0].type, 'switch.quota');
  assert.equal(dataLines[0].provider, 'claude');
  assert.equal(dataLines[0].from, 'a@x.com');
  assert.equal(dataLines[0].to, 'b@x.com');
  assert.equal(dataLines[0].source, 'main.log');
  assert.equal(dataLines[1].type, 'switch.auth');

  status = JSON.parse((await get(port, '/status')).body);
  assert.equal(status.switches, 2);
  assert.equal(status.lastSwitch.type, 'switch.auth');
  assert.deepEqual(status.byType, { 'switch.quota': 1, 'switch.auth': 1 });
  assert.deepEqual(status.watching, ['main.log']);

  // SSE resume: Last-Event-ID replays what a reconnecting client missed
  const resumed = await new Promise((resolve, reject) => {
    const r = http.get({ host: '127.0.0.1', port, path: '/events', headers: { 'Last-Event-ID': '1' } }, (res) => {
      res.setEncoding('utf8');
      let buf = '';
      res.on('data', (d) => {
        buf += d;
        if (buf.includes('switch.auth')) {
          r.destroy();
          resolve(buf);
        }
      });
    });
    r.on('error', (e) => (e.code === 'ECONNRESET' ? undefined : reject(e)));
  });
  assert.ok(!resumed.includes('switch.quota'));

  // JSONL audit trail
  await app.hub.flush();
  const lines = (await fsp.readFile(switchLog, 'utf8')).trim().split('\n').map((l) => JSON.parse(l));
  assert.deepEqual(lines.map((l) => l.type), ['switch.quota', 'switch.auth']);

  sseReq.destroy();

  // a restarted service restores its counters from the JSONL file
  const app2 = createApp(
    { logDir, switchLog, port: 0, host: '127.0.0.1', pollMs: 50, dedupeMs: 0, replay: false, includeDebug: false, corsOrigin: '', proxyUrl: '' },
    quiet,
  );
  const port2 = await app2.start();
  try {
    const s2 = JSON.parse((await get(port2, '/status')).body);
    assert.equal(s2.switches, 2);
    assert.equal(s2.lastSwitch.type, 'switch.auth');
  } finally {
    await app2.stop();
  }
});

test('service: duplicate bursts are deduped', async () => {
  const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'rahbaz-sn-'));
  const app = createApp(
    { logDir: path.join(tmp, 'logs'), switchLog: path.join(tmp, 'o', 's.jsonl'), port: 0, host: '127.0.0.1', pollMs: 50, dedupeMs: 60000, replay: false, includeDebug: false, corsOrigin: '', proxyUrl: '' },
    quiet,
  );
  await app.start();
  try {
    const line = 'level=warn msg="claude 429 rate limit"';
    assert.equal(app.hub.publish(detectLine(line)), true);
    assert.equal(app.hub.publish(detectLine(line)), false);
    assert.equal(app.hub.status().switches, 1);
  } finally {
    await app.stop();
    await fsp.rm(tmp, { recursive: true, force: true });
  }
});
