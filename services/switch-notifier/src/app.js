'use strict';

const http = require('node:http');
const path = require('node:path');
const { detectLine } = require('./detector');
const { LogTailer } = require('./tailer');
const { SwitchHub } = require('./hub');

const HEARTBEAT_MS = 15000;

function loadConfig(env = process.env) {
  const int = (v, d) => (Number.isFinite(Number(v)) && v !== undefined && v !== '' ? Number(v) : d);
  const flag = (v) => /^(1|true|yes|on)$/i.test(v || '');
  return {
    logDir: env.RAHBAZ_LOG_DIR || path.resolve('logs', 'cliproxy'),
    switchLog: env.RAHBAZ_SWITCH_LOG || path.resolve('logs', 'notifier', 'switches.jsonl'),
    port: int(env.RAHBAZ_PORT, 8791),
    host: env.RAHBAZ_HOST || '0.0.0.0',
    proxyUrl: env.RAHBAZ_PROXY_URL || '',
    pollMs: int(env.RAHBAZ_POLL_MS, 1000),
    dedupeMs: int(env.RAHBAZ_DEDUPE_MS, 2000),
    replay: flag(env.RAHBAZ_REPLAY), // read existing log content from the start on boot
    includeDebug: flag(env.RAHBAZ_INCLUDE_DEBUG),
    corsOrigin: env.RAHBAZ_CORS_ORIGIN || '', // empty = no CORS headers (loopback tools only)
  };
}

function createApp(config = loadConfig(), log = console) {
  const hub = new SwitchHub({ logPath: config.switchLog, dedupeMs: config.dedupeMs, log });
  const tailer = new LogTailer({
    dir: config.logDir,
    pollMs: config.pollMs,
    startAtEnd: !config.replay,
    exclude: config.switchLog ? [config.switchLog] : [],
    log,
    onLine: (line, source) => {
      const ev = detectLine(line, { source, includeDebug: config.includeDebug });
      if (ev) hub.publish(ev);
    },
  });

  const sseClients = new Set();

  function json(res, code, body) {
    const data = JSON.stringify(body);
    res.writeHead(code, {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Length': Buffer.byteLength(data),
      'Cache-Control': 'no-store',
      ...corsHeaders(),
    });
    res.end(data);
  }

  function corsHeaders() {
    return config.corsOrigin ? { 'Access-Control-Allow-Origin': config.corsOrigin } : {};
  }

  function sse(entry) {
    return `id: ${entry.id}\ndata: ${JSON.stringify(entry.event)}\n\n`;
  }

  function handleEvents(req, res, url) {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
      ...corsHeaders(),
    });
    req.socket.setTimeout(0);
    req.socket.setNoDelay(true);
    res.write('retry: 3000\n: connected\n\n');

    // Resume support: Last-Event-ID header (or ?lastEventId=) replays missed events;
    // ?replay=N replays the last N events on connect.
    const lastId = Number(req.headers['last-event-id'] ?? url.searchParams.get('lastEventId'));
    const replayN = Number(url.searchParams.get('replay'));
    const backlog = Number.isFinite(lastId) && lastId >= 0 && (req.headers['last-event-id'] || url.searchParams.has('lastEventId'))
      ? hub.since(lastId)
      : Number.isFinite(replayN) && replayN > 0
        ? hub.last(replayN)
        : [];
    for (const entry of backlog) res.write(sse(entry));

    const onEvent = (entry) => res.write(sse(entry));
    hub.on('event', onEvent);
    const beat = setInterval(() => res.write(': ping\n\n'), HEARTBEAT_MS);
    const client = { res, cleanup: () => {} };
    client.cleanup = () => {
      clearInterval(beat);
      hub.off('event', onEvent);
      sseClients.delete(client);
    };
    sseClients.add(client);
    req.on('close', client.cleanup);
  }

  const server = http.createServer((req, res) => {
    let url;
    try {
      url = new URL(req.url, 'http://localhost');
    } catch {
      return json(res, 400, { ok: false, error: 'bad request' });
    }

    if (req.method === 'OPTIONS') {
      res.writeHead(204, {
        ...corsHeaders(),
        'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
        'Access-Control-Allow-Headers': 'Last-Event-ID',
      });
      return res.end();
    }
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.setHeader('Allow', 'GET, HEAD, OPTIONS');
      return json(res, 405, { ok: false, error: 'method not allowed' });
    }

    switch (url.pathname) {
      case '/health':
        return json(res, 200, { ok: true });
      case '/status':
        return json(res, 200, {
          ok: true,
          ...hub.status(),
          watching: tailer.watching(),
          logDir: config.logDir,
          proxyUrl: config.proxyUrl || undefined,
          sseClients: sseClients.size,
        });
      case '/events':
        return handleEvents(req, res, url);
      case '/':
        return json(res, 200, { ok: true, service: 'rahbaz-switch-notifier', endpoints: ['/health', '/status', '/events'] });
      default:
        return json(res, 404, { ok: false, error: 'not found' });
    }
  });

  return {
    server,
    hub,
    tailer,
    config,
    async start() {
      await hub.init();
      await new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(config.port, config.host, () => {
          server.off('error', reject);
          resolve();
        });
      });
      await tailer.start();
      return server.address().port;
    },
    async stop() {
      tailer.stop();
      for (const c of [...sseClients]) {
        c.cleanup();
        c.res.end();
      }
      await new Promise((resolve) => {
        server.close(() => resolve());
        server.closeAllConnections?.();
      });
      await hub.flush();
    },
  };
}

module.exports = { createApp, loadConfig };
