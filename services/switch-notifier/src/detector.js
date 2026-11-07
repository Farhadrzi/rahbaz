'use strict';

/**
 * Heuristic detector: one log line in -> zero or one switch event out.
 *
 * The upstream proxy (CLIProxyAPI) has no stable "switch" log format, so this is
 * deliberately liberal: it looks for HTTP status codes in several common layouts,
 * quota / auth / upstream-error vocabulary, and explicit failover wording.
 *
 * Classification priority: quota > auth > error > unknown.
 *   - switch.quota   rate limits, quota exhaustion, 429 / 402
 *   - switch.auth    401 / 403, expired or revoked tokens, failed refresh
 *   - switch.error   5xx, overloaded, timeouts, connection resets
 *   - switch.unknown failover / rotate / rebind / cooldown wording with no clear cause
 *
 * Sample lines that produce events (see test/selfcheck.test.js for the full set):
 *   [GIN] 2026/01/01 - 12:00:00 | 429 | 1.2s | 127.0.0.1 | POST "/v1/messages"
 *   time="..." level=warn msg="upstream 429 Too Many Requests for claude auth a@x.com, cooling down"
 *   [warn] switching from auth claude-a@x.com to claude-b@x.com after quota exceeded
 *   {"level":"warn","msg":"token refresh failed","provider":"codex","auth_id":"c1","status":401}
 *   level=error msg="upstream returned 503 overloaded_error" provider=anthropic
 *   [info] failover from codex-a to codex-b
 *   level=info msg="auth codex-a is cooling down for 30m"
 *
 * Lines that are ignored: ordinary 2xx access logs, "Switching Protocols",
 * and debug-level lines (request/response dumps can contain arbitrary user text).
 */

const MAX_LINE = 4000; // never run regexes over more than this
const RAW_MAX = 500; // max chars of the original line kept in event.raw

/* ------------------------------------------------------------------ status */

// Each pattern captures a 3-digit HTTP status in a layout we have seen in proxy logs.
const STATUS_PATTERNS = [
  // gin access log:  | 429 |
  /\|\s*(\d{3})\s*\|/g,
  // status=429  status_code: 429  "status":429  http 429  code=429  HTTP/1.1 429
  /\b(?:status(?:[_ -]?code)?|http(?:[_ -]?status)?|code|HTTP\/\d(?:\.\d)?)["']?\s*[=:]?\s*["']?(\d{3})\b/gi,
  // 429 Too Many Requests
  /\b(\d{3})\s+(?:too many requests|unauthorized|forbidden|payment required|bad gateway|service unavailable|gateway timeout|internal server error)/gi,
];

function statusCodes(text) {
  const codes = [];
  for (const re of STATUS_PATTERNS) {
    re.lastIndex = 0;
    for (const m of text.matchAll(re)) {
      const n = Number(m[1]);
      if (n >= 400 && n <= 599 && !codes.includes(n)) codes.push(n);
    }
  }
  return codes;
}

/* ------------------------------------------------------------------- rules */

// [regex, label]. Labels end up (joined) in event.reason.
const QUOTA_RULES = [
  [/\bquota\b/i, 'quota'],
  [/\brate[ _-]?limit(?:ed|s|ing)?\b/i, 'rate limit'],
  [/\btoo many requests\b/i, 'too many requests'],
  [/\bresource[_ ]?exhausted\b/i, 'resource exhausted'],
  [/\b(?:usage|credit|token|request)s?[ _-]limit\b/i, 'usage limit'],
  [/\blimit (?:reached|exceeded|hit)\b/i, 'limit reached'],
  [/\bexceeded\b[^.\n]{0,40}\b(?:limit|quota|usage)\b/i, 'limit exceeded'],
  [/\b(?:5|five)[- ]hour (?:limit|window)\b|\bweekly limit\b/i, 'subscription window limit'],
  [/\binsufficient[_ ](?:quota|credits?|balance)\b|\bcredit balance\b|\bout of (?:credits|usage)\b/i, 'insufficient credits'],
  [/\bmodel[_ ]cooldown\b/i, 'model cooldown'],
];

const AUTH_RULES = [
  [/\bunauthori[sz]ed\b/i, 'unauthorized'],
  [/\binvalid[_ ](?:api[_ ]?key|token|credentials?|grant|x-api-key)\b/i, 'invalid credential'],
  [/\bauthentication[_ ](?:error|failed|failure)\b|\bauth(?:entication)? fail(?:ed|ure)?\b/i, 'authentication failed'],
  [/\btoken\b[^.\n]{0,20}\b(?:expired|revoked|invalid)\b|\bexpired[_ ](?:token|credential|session)\b/i, 'token expired'],
  [/\b(?:refresh(?:[ _]token)?|token refresh)\b[^.\n]{0,20}\b(?:failed|error|denied)\b|\bfailed to refresh\b/i, 'refresh failed'],
  [/\bpermission[_ ]denied\b|\bforbidden\b/i, 'forbidden'],
  [/\b(?:login|re-?auth(?:enticat\w+)?) (?:required|needed)\b/i, 'reauth required'],
  [/\b(?:account|credential|auth)\b[^.\n]{0,30}\b(?:suspended|banned|disabled|deactivated|revoked)\b/i, 'account disabled'],
];

const ERROR_RULES = [
  [/\boverloaded(?:_error)?\b/i, 'overloaded'],
  [/\b(?:bad gateway|service unavailable|gateway timeout|internal server error)\b/i, 'upstream 5xx'],
  [/\bupstream\b[^.\n]{0,30}\b(?:error|failed|failure|timeout|timed out|unavailable)\b/i, 'upstream error'],
  [/\b(?:connection (?:reset|refused|closed)|ECONNRESET|ECONNREFUSED|ETIMEDOUT|context deadline exceeded)\b/i, 'connection error'],
  [/\bapi_error\b|\bserver_error\b/i, 'api error'],
  [/\bstream\b[^.\n]{0,30}\b(?:error|aborted|interrupted|closed unexpectedly)\b/i, 'stream error'],
];

// Explicit "we are moving to a different credential" wording. Used both to
// enrich classified events and, on its own, to emit switch.unknown.
const SWITCH_HINTS = [
  [/\bfail(?:ed|ing)?[ _-]?over\b/i, 'failover'],
  [/\bfall(?:ing)? ?back\b/i, 'fallback'],
  [/\bswitch(?:ed|ing|es)?\b[^.\n]{0,40}\b(?:account|auth|credential|key|provider|upstream|channel)\b/i, 'switch'],
  [/\brotat(?:e|ed|es|ing|ion)\b[^.\n]{0,40}\b(?:account|auth|credential|key)\b/i, 'rotate'],
  [/\brebind(?:ing|s|ed)?\b|\brebound\b/i, 'rebind'],
  [/\b(?:retry(?:ing)?|try(?:ing)?)\b[^.\n]{0,30}\b(?:next|another|other)\b[^.\n]{0,20}\b(?:account|auth|credential|key)\b/i, 'retry next'],
  [/\b(?:next|another)[ _-](?:auth|credential|account)\b/i, 'next credential'],
  [/\bcool(?:ing|ed|s)?[ _-]?down\b|\bcooldown\b/i, 'cooldown'],
  [/\bmarked\s+(?:as\s+)?(?:unavailable|suspended|exhausted)\b/i, 'marked unavailable'],
];

const DEBUG_RE = /\blevel=["']?debug\b|\[debug\]|\bDEBU\b/i;

/* --------------------------------------------------------------- providers */

const PROVIDERS = [
  ['antigravity', /\bantigravity\b/i],
  ['claude', /\b(?:claude|anthropic)\b/i],
  ['codex', /\b(?:codex|openai|chatgpt|gpt-[\w.-]+)\b/i],
  ['gemini', /\b(?:gemini|google|vertex|aistudio)\b/i],
  ['qwen', /\bqwen\b/i],
  ['iflow', /\biflow\b/i],
  ['kimi', /\bkimi\b/i],
];

function detectProvider(text) {
  const explicit = text.match(/\bprovider["']?\s*[=:]\s*["']?([\w.-]+)/i);
  if (explicit) {
    const v = explicit[1].toLowerCase();
    for (const [name, re] of PROVIDERS) if (re.test(v)) return name;
    return v;
  }
  for (const [name, re] of PROVIDERS) if (re.test(text)) return name;
  return undefined;
}

/* -------------------------------------------------------------- from / to */

// Must start with alnum so "from auth-a to auth-b" keeps the full id (not "-a").
const ID = '([A-Za-z0-9][\\w.@+-]*)';

const FROM_TO_ARROW = new RegExp(
  `\\bfrom\\s+(?:(?:auth|credential|account|key|provider)\\s+)?['"]?${ID}['"]?\\s*(?:->|→|=>|\\bto\\b)\\s+(?:(?:auth|credential|account|key|provider)\\s+)?['"]?${ID}`,
  'i',
);
const FROM_KV = new RegExp(
  `\\bfrom(?:[_-](?:auth|credential|account))?(?:[_-]?id)?["']?\\s*[=:]\\s*["']?${ID}`,
  'i',
);
const TO_KV = new RegExp(
  `\\b(?:to(?:[_-](?:auth|credential|account))?|(?:next|new)[_-](?:auth|credential|account))(?:[_-]?id)?["']?\\s*[=:]\\s*["']?${ID}`,
  'i',
);
const NEXT_WORDS = new RegExp(
  `\\b(?:next|another|new)\\s+(?:auth|credential|account)\\s*['"]?${ID}`,
  'i',
);
const CURRENT_AUTH = new RegExp(
  `\\b(?:auth(?:[_-]?id)?|credential|account)["']?\\s*[=:]\\s*["']?${ID}`,
  'i',
);
// "claude auth a@x.com, cooling down" / "account codex-1 hit the limit"
const AUTH_WORD = new RegExp(`\\b(?:auth|credential|account)\\s+['"]?${ID}['"]?(?=[\\s,;:)]|$)`, 'gi');
const LOOKS_LIKE_ID = /[@\d_-]/; // avoids "auth failed" -> from="failed"

function extractFromTo(text) {
  let from;
  let to;
  const arrow = text.match(FROM_TO_ARROW);
  if (arrow) {
    from = arrow[1];
    to = arrow[2];
  } else {
    from = text.match(FROM_KV)?.[1];
    to = text.match(TO_KV)?.[1] ?? text.match(NEXT_WORDS)?.[1];
  }
  if (!from) {
    // The credential that is *currently failing* is the one we are switching away from.
    from = text.match(CURRENT_AUTH)?.[1];
    if (!from) {
      for (const m of text.matchAll(AUTH_WORD)) {
        if (LOOKS_LIKE_ID.test(m[1])) {
          from = m[1];
          break;
        }
      }
    }
  }
  if (from && to && from === to) to = undefined;
  return { from, to };
}

/* --------------------------------------------------------------- redaction */

const REDACTIONS = [
  [/\bBearer\s+[\w.~+/=-]{6,}/gi, 'Bearer [redacted]'],
  [/\bsk-[\w-]{8,}/g, 'sk-[redacted]'],
  [/\beyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]*/g, '[redacted-jwt]'],
  [
    /\b((?:api[-_]?key|x-api-key|access[-_]?token|refresh[-_]?token|id[-_]?token|token|secret|password|authorization)["']?\s*[=:]\s*["']?)[^\s"',}]{4,}/gi,
    '$1[redacted]',
  ],
];

function redact(text) {
  let out = text;
  for (const [re, rep] of REDACTIONS) out = out.replace(re, rep);
  return out;
}

/* ------------------------------------------------------------------- JSON */

function flattenJson(obj, out = [], depth = 0) {
  if (obj === null || typeof obj !== 'object' || depth > 3) return out;
  for (const [k, v] of Object.entries(obj)) {
    if (v === null || v === undefined) continue;
    if (typeof v === 'object') flattenJson(v, out, depth + 1);
    else out.push(`${k}=${v}`);
  }
  return out;
}

function toText(line) {
  const trimmed = line.trim();
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
    try {
      const obj = JSON.parse(trimmed);
      if (obj && typeof obj === 'object') return flattenJson(obj).join(' ');
    } catch {
      /* not JSON after all; fall through */
    }
  }
  return trimmed;
}

/* ---------------------------------------------------------------- matching */

function matchRules(rules, text) {
  const labels = [];
  for (const [re, label] of rules) if (re.test(text)) labels.push(label);
  return labels;
}

/**
 * @param {string} line
 * @param {{source?: string, includeDebug?: boolean, now?: Date}} [opts]
 * @returns {null | {ts:string,type:string,provider?:string,from?:string,to?:string,reason:string,raw?:string,source?:string}}
 */
function detectLine(line, opts = {}) {
  if (typeof line !== 'string' || line.length === 0) return null;
  const clipped = line.length > MAX_LINE ? line.slice(0, MAX_LINE) : line;
  const text = toText(clipped);
  if (!text) return null;
  if (!opts.includeDebug && DEBUG_RE.test(text)) return null;

  const codes = statusCodes(text);
  const hints = matchRules(SWITCH_HINTS, text);

  const quota = matchRules(QUOTA_RULES, text);
  const auth = matchRules(AUTH_RULES, text);
  const error = matchRules(ERROR_RULES, text);

  const has = (...wanted) => codes.some((c) => wanted.includes(c));
  const has5xx = codes.some((c) => c >= 500);

  let type;
  let labels;
  if (quota.length || has(429, 402)) {
    type = 'switch.quota';
    labels = [...codes.filter((c) => c === 429 || c === 402).map((c) => `http ${c}`), ...quota];
  } else if (auth.length || has(401, 403)) {
    type = 'switch.auth';
    labels = [...codes.filter((c) => c === 401 || c === 403).map((c) => `http ${c}`), ...auth];
  } else if (error.length || has5xx) {
    type = 'switch.error';
    labels = [...codes.filter((c) => c >= 500).map((c) => `http ${c}`), ...error];
  } else if (hints.length) {
    type = 'switch.unknown';
    labels = [];
  } else {
    return null;
  }

  const reason = [...new Set([...labels, ...hints])].slice(0, 4).join('; ');
  const { from, to } = extractFromTo(text);

  const event = {
    ts: (opts.now ?? new Date()).toISOString(),
    type,
  };
  const provider = detectProvider(text);
  if (provider) event.provider = provider;
  if (from) event.from = from;
  if (to) event.to = to;
  event.reason = reason || 'unspecified';
  event.raw = redact(clipped.trim()).slice(0, RAW_MAX);
  if (opts.source) event.source = opts.source;
  return event;
}

module.exports = { detectLine, redact, statusCodes, detectProvider };
