# switch-notifier

RahBaz sidecar that watches the CLIProxyAPI logs and turns failover / quota / auth / cooldown
lines into structured **switch events** (SPEC FR4, FR5).

- Zero runtime dependencies (Node 22, built-ins only)
- Tails every log-ish file under `RAHBAZ_LOG_DIR` (polling, so it works on Docker Desktop bind mounts)
- Publishes events over SSE, appends them to a JSONL audit file, and exposes a tiny status API

## Endpoints

| Method | Path       | Response |
|--------|------------|----------|
| GET    | `/health`  | `{"ok":true}` |
| GET    | `/status`  | `{ok, switches, lastSwitch, byType, startedAt, uptimeSec, auditLog, auditLogWritable, watching[], logDir, proxyUrl, sseClients}` |
| GET    | `/events`  | `text/event-stream`, one unnamed `data:` message per switch event |

```sh
curl http://127.0.0.1:8791/health
curl http://127.0.0.1:8791/status
curl -N http://127.0.0.1:8791/events                 # live
curl -N "http://127.0.0.1:8791/events?replay=10"     # last 10 events, then live
```

SSE details: each message carries `id:` (a running count of switches). Reconnecting with
`Last-Event-ID` (EventSource does this automatically) replays what was missed, bounded by the
last 200 events held in memory. A `: ping` comment is sent every 15 s.
Because messages are unnamed, `EventSource.onmessage` receives them; the event type is in the JSON.

## Event shape

```json
{
  "ts": "2026-01-01T12:00:00.000Z",
  "type": "switch.quota",
  "provider": "claude",
  "from": "claude-a@example.com",
  "to": "claude-b@example.com",
  "reason": "http 429; rate limit; switch",
  "raw": "level=warn msg=\"claude auth ...\"",
  "source": "main.log"
}
```

| `type`           | Meaning |
|------------------|---------|
| `switch.quota`   | 429 / 402, rate limit, quota or usage-window exhaustion |
| `switch.auth`    | 401 / 403, expired or revoked token, failed refresh, disabled account |
| `switch.error`   | 5xx, overloaded, upstream timeout, connection reset, stream error |
| `switch.unknown` | failover / rotate / rebind / cooldown wording with no recognisable cause |

`provider`, `from`, `to`, `raw` and `source` are optional. `ts` is the time the line was *detected*,
not parsed from the log line. `raw` is truncated to 500 chars and has bearer tokens, `sk-` keys,
JWTs and `token=`/`api_key=`-style values redacted. (`switch.manual` from the spec is future work.)

## How detection works

`src/detector.js` is heuristic on purpose: the proxy has no stable "switch" log format. It finds
HTTP status codes in several layouts (gin `| 429 |`, `status=429`, `HTTP/1.1 429`, `429 Too Many Requests`),
matches quota/auth/error vocabulary, and recognises explicit failover wording. JSON log lines are
flattened to `key=value` first. Priority is quota > auth > error > unknown. **Debug-level lines are
ignored** by default because request/response dumps can contain arbitrary text.
Sample lines are documented at the top of the file and exercised in `test/selfcheck.test.js`.
Expect to tune the regexes once you see real proxy output.

Identical events (same type/provider/from/to/reason) within `RAHBAZ_DEDUPE_MS` are collapsed.

Files already present when the service starts are read from the **end** (no replay of old history on
restart); files that appear later are read from the start. Missing or empty log dirs are fine.
Set `RAHBAZ_REPLAY=1` to read existing files from the beginning.

## Configuration

| Variable | Default | Notes |
|----------|---------|-------|
| `RAHBAZ_LOG_DIR` | `./logs/cliproxy` | Directory to tail. Created if possible (a read-only mount is tolerated). |
| `RAHBAZ_SWITCH_LOG` | `./logs/notifier/switches.jsonl` | JSONL audit file; parent dir created. On boot, counters and the replay ring are restored from it. |
| `RAHBAZ_PORT` | `8791` | |
| `RAHBAZ_HOST` | `0.0.0.0` | Compose publishes the port on `127.0.0.1` only. |
| `RAHBAZ_PROXY_URL` | _(empty)_ | Reported in `/status`; not polled yet. |
| `RAHBAZ_POLL_MS` | `1000` | Log poll interval. |
| `RAHBAZ_DEDUPE_MS` | `2000` | `0` disables dedupe. |
| `RAHBAZ_REPLAY` | off | Read existing files from the start on boot. |
| `RAHBAZ_INCLUDE_DEBUG` | off | Also inspect debug-level lines. |
| `RAHBAZ_CORS_ORIGIN` | _(none)_ | No CORS headers unless set. |

If the audit file cannot be written (for example a Linux host where `./logs/notifier` is owned by
root while the container runs as `node`), the service keeps running, logs a warning once, and
`/status` reports `auditLogWritable: false`. Fix with `chown -R 1000:1000 logs/notifier` or by
setting `user: root` in a compose override.

## Run

Docker (from the repo root):

```sh
docker compose build switch-notifier
docker compose up -d switch-notifier   # also starts cliproxy (depends_on)
curl http://127.0.0.1:8791/status
```

Locally without Docker:

```sh
cd services/switch-notifier
RAHBAZ_LOG_DIR=./tmp/logs RAHBAZ_SWITCH_LOG=./tmp/out/switches.jsonl node src/server.js
# in another shell:
echo 'level=warn msg="claude 429 rate limit, failover from a to b"' >> tmp/logs/main.log
curl http://127.0.0.1:8791/status
```

## Test

```sh
cd services/switch-notifier
npm test
```

No Docker or network needed. It feeds sample log lines to the detector (positive and negative cases,
redaction, debug filtering), then starts the full service on a random port against a temp dir and
asserts a log line written *after* startup produces an SSE event, a `/status` update, a JSONL line,
Last-Event-ID resume, and counter restore after restart.
