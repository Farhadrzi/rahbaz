'use strict';

const fsp = require('node:fs/promises');
const path = require('node:path');
const { StringDecoder } = require('node:string_decoder');

const MAX_DEPTH = 3;
const MAX_READ_PER_TICK = 4 * 1024 * 1024; // per file, per poll
const READ_CHUNK = 256 * 1024;
const MAX_CARRY = 64 * 1024; // longest partial line we will buffer

const SKIP_EXT = new Set(['.gz', '.zip', '.bz2', '.xz', '.zst', '.tmp', '.bak', '.swp', '.db', '.sqlite']);
const TAIL_EXT = new Set(['.log', '.txt', '.jsonl', '.ndjson', '.out', '']);

function isLogFile(name) {
  const ext = path.extname(name).toLowerCase();
  if (SKIP_EXT.has(ext)) return false;
  return TAIL_EXT.has(ext) || /log/i.test(name);
}

/**
 * Polling tailer for every log-ish file under a directory (recursive, shallow).
 *
 * Polling (not fs.watch) on purpose: inotify events do not cross Docker Desktop
 * bind mounts from Windows reliably. Tolerates a missing/empty directory and files
 * that appear later (the proxy may not have written anything yet), truncation and
 * rotation (size shrink or inode change -> restart from 0).
 */
class LogTailer {
  /**
   * @param {object} o
   * @param {string} o.dir
   * @param {(line:string, source:string)=>void} o.onLine
   * @param {number} [o.pollMs]
   * @param {boolean} [o.startAtEnd]  files present at startup are read from EOF (default true)
   * @param {string[]} [o.exclude]    absolute paths never to tail (e.g. our own output)
   * @param {{warn:Function}} [o.log]
   */
  constructor({ dir, onLine, pollMs = 1000, startAtEnd = true, exclude = [], log = console }) {
    this.dir = path.resolve(dir);
    this.onLine = onLine;
    this.pollMs = pollMs;
    this.startAtEnd = startAtEnd;
    this.exclude = new Set(exclude.map((p) => path.resolve(p)));
    this.log = log;
    this.files = new Map(); // fullPath -> state
    this.timer = null;
    this.scanning = false;
    this.firstScan = true;
    this.stopped = false;
  }

  async start() {
    try {
      await fsp.mkdir(this.dir, { recursive: true });
    } catch (err) {
      // Read-only mount or permission problem: fine as long as the dir exists / appears.
      this.log.warn(`[tailer] cannot create ${this.dir} (${err.code || err.message}); will keep waiting for it`);
    }
    await this.scan();
    if (!this.stopped) {
      this.timer = setInterval(() => void this.scan(), this.pollMs);
    }
  }

  stop() {
    this.stopped = true;
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  watching() {
    return [...this.files.keys()].map((f) => path.relative(this.dir, f) || f);
  }

  async listFiles(dir, depth = 0, out = []) {
    let entries;
    try {
      entries = await fsp.readdir(dir, { withFileTypes: true });
    } catch {
      return out; // missing dir or unreadable: nothing to tail yet
    }
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (depth < MAX_DEPTH) await this.listFiles(full, depth + 1, out);
      } else if (e.isFile() && isLogFile(e.name) && !this.exclude.has(full)) {
        out.push(full);
      }
    }
    return out;
  }

  async scan() {
    if (this.scanning || this.stopped) return;
    this.scanning = true;
    try {
      const found = await this.listFiles(this.dir);
      const seen = new Set(found);
      for (const full of this.files.keys()) if (!seen.has(full)) this.files.delete(full);

      for (const full of found) {
        try {
          await this.poll(full);
        } catch (err) {
          if (err.code !== 'ENOENT') this.log.warn(`[tailer] ${full}: ${err.code || err.message}`);
        }
      }
    } finally {
      this.firstScan = false;
      this.scanning = false;
    }
  }

  async poll(full) {
    const st = await fsp.stat(full);
    let state = this.files.get(full);
    if (!state) {
      state = {
        offset: this.firstScan && this.startAtEnd ? st.size : 0,
        ino: st.ino,
        carry: '',
        decoder: new StringDecoder('utf8'),
        source: path.relative(this.dir, full) || path.basename(full),
      };
      this.files.set(full, state);
    }

    // Rotation (new inode; ino can be 0 on some Windows mounts) or truncation.
    const rotated = st.ino && state.ino && st.ino !== state.ino;
    if (rotated || st.size < state.offset) {
      state.offset = 0;
      state.carry = '';
      state.decoder = new StringDecoder('utf8');
    }
    state.ino = st.ino;

    if (st.size > state.offset) await this.drain(full, state, st.size);
  }

  async drain(full, state, size) {
    const fh = await fsp.open(full, 'r');
    try {
      let remaining = Math.min(size - state.offset, MAX_READ_PER_TICK);
      const buf = Buffer.allocUnsafe(Math.min(remaining, READ_CHUNK));
      while (remaining > 0 && !this.stopped) {
        const want = Math.min(buf.length, remaining);
        const { bytesRead } = await fh.read(buf, 0, want, state.offset);
        if (bytesRead === 0) break;
        state.offset += bytesRead;
        remaining -= bytesRead;
        state.carry += state.decoder.write(buf.subarray(0, bytesRead));
        this.emitLines(state);
      }
    } finally {
      await fh.close();
    }
  }

  emitLines(state) {
    const parts = state.carry.split('\n');
    state.carry = parts.pop() ?? '';
    if (state.carry.length > MAX_CARRY) state.carry = state.carry.slice(-MAX_CARRY);
    for (const raw of parts) {
      const line = raw.endsWith('\r') ? raw.slice(0, -1) : raw;
      if (!line) continue;
      try {
        this.onLine(line, state.source);
      } catch (err) {
        this.log.warn(`[tailer] onLine failed: ${err.message}`);
      }
    }
  }
}

module.exports = { LogTailer, isLogFile };
