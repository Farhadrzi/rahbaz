'use strict';

const { EventEmitter } = require('node:events');
const fsp = require('node:fs/promises');
const path = require('node:path');

const RESTORE_MAX_BYTES = 20 * 1024 * 1024; // don't slurp a huge audit log on boot

/**
 * In-memory event hub: dedupes bursts, keeps a replay ring for SSE, counts
 * switches, and appends every event to a JSONL audit file.
 *
 * Emits 'event' with {id, event}. `id` is a monotonically increasing sequence
 * (== total switches so far, including those restored from the JSONL file), used
 * as the SSE `id:` so clients can resume with Last-Event-ID.
 */
class SwitchHub extends EventEmitter {
  constructor({ logPath, ringSize = 200, dedupeMs = 2000, log = console }) {
    super();
    this.logPath = logPath ? path.resolve(logPath) : null;
    this.ringSize = ringSize;
    this.dedupeMs = dedupeMs;
    this.log = log;
    this.startedAt = new Date();
    this.total = 0;
    this.byType = {};
    this.lastSwitch = null;
    this.ring = []; // [{id, event}]
    this.recent = new Map(); // dedupe key -> epoch ms
    this.queue = Promise.resolve();
    this.writeFailed = false;
  }

  /** Create the output dir and restore counters/ring from an existing JSONL file. */
  async init() {
    if (!this.logPath) return;
    try {
      await fsp.mkdir(path.dirname(this.logPath), { recursive: true });
    } catch (err) {
      this.log.warn(`[hub] cannot create ${path.dirname(this.logPath)} (${err.code || err.message}); events stay in memory only`);
      return;
    }
    try {
      const st = await fsp.stat(this.logPath);
      if (st.size > RESTORE_MAX_BYTES) {
        this.log.warn(`[hub] ${this.logPath} is ${st.size} bytes; skipping restore`);
        return;
      }
      const text = await fsp.readFile(this.logPath, 'utf8');
      for (const line of text.split('\n')) {
        if (!line.trim()) continue;
        let ev;
        try {
          ev = JSON.parse(line);
        } catch {
          continue;
        }
        if (!ev || typeof ev.type !== 'string') continue;
        this.record(ev);
      }
    } catch (err) {
      if (err.code !== 'ENOENT') this.log.warn(`[hub] restore failed: ${err.message}`);
    }
  }

  record(event) {
    this.total += 1;
    this.byType[event.type] = (this.byType[event.type] || 0) + 1;
    this.lastSwitch = event;
    const entry = { id: this.total, event };
    this.ring.push(entry);
    if (this.ring.length > this.ringSize) this.ring.shift();
    return entry;
  }

  /** @returns {boolean} false if suppressed as a duplicate burst */
  publish(event) {
    const key = [event.type, event.provider, event.from, event.to, event.reason].join('|');
    const now = Date.now();
    const prev = this.recent.get(key);
    if (this.dedupeMs > 0 && prev !== undefined && now - prev < this.dedupeMs) return false;
    this.recent.set(key, now);
    if (this.recent.size > 500) {
      for (const [k, t] of this.recent) if (now - t >= this.dedupeMs) this.recent.delete(k);
    }

    const entry = this.record(event);
    this.append(event);
    this.emit('event', entry);
    return true;
  }

  append(event) {
    if (!this.logPath) return;
    const line = `${JSON.stringify(event)}\n`;
    this.queue = this.queue
      .then(() => fsp.appendFile(this.logPath, line))
      .then(() => {
        this.writeFailed = false;
      })
      .catch((err) => {
        if (!this.writeFailed) this.log.warn(`[hub] cannot append to ${this.logPath}: ${err.code || err.message}`);
        this.writeFailed = true;
      });
  }

  /** Events with id > lastId (bounded by the ring). */
  since(lastId) {
    return this.ring.filter((e) => e.id > lastId);
  }

  last(n) {
    return n > 0 ? this.ring.slice(-n) : [];
  }

  flush() {
    return this.queue;
  }

  status() {
    return {
      switches: this.total,
      lastSwitch: this.lastSwitch,
      byType: this.byType,
      startedAt: this.startedAt.toISOString(),
      uptimeSec: Math.round((Date.now() - this.startedAt.getTime()) / 1000),
      auditLog: this.logPath,
      auditLogWritable: !this.writeFailed,
    };
  }
}

module.exports = { SwitchHub };
