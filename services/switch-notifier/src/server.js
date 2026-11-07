#!/usr/bin/env node
'use strict';

const { createApp, loadConfig } = require('./app');

const config = loadConfig();
const app = createApp(config);

app
  .start()
  .then((port) => {
    console.log(`[switch-notifier] listening on ${config.host}:${port}`);
    console.log(`[switch-notifier] tailing ${config.logDir} -> ${config.switchLog}`);
  })
  .catch((err) => {
    console.error(`[switch-notifier] failed to start: ${err.stack || err.message}`);
    process.exit(1);
  });

let shuttingDown = false;
async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`[switch-notifier] ${signal}, shutting down`);
  const force = setTimeout(() => process.exit(0), 3000);
  force.unref();
  try {
    await app.stop();
  } finally {
    process.exit(0);
  }
}
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
