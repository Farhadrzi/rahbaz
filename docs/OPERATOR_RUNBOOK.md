# RahBaz Hub Operator Runbook

Day-2 operations for **RahBaz Hub** (local OpenRouter-style gateway) on Windows + Docker Desktop. The Hub owns accounts, model catalog (`/v1/models`), weights, and failover. **RahBaz Client** (T3 fork) only connects here — see [CLIENT.md](CLIENT.md).

All commands are Windows PowerShell, run from the repo root. Everything is bound to `127.0.0.1` only.

| Thing | Where |
|---|---|
| Gateway API | `http://127.0.0.1:8317` (Claude base URL) / `http://127.0.0.1:8317/v1` (OpenAI/Codex) |
| Hub dashboard (Web UI) | `http://127.0.0.1:8317/management.html` — log in with the **management** key (not the gateway API key). Needs `management.allow-remote: true` under Docker Desktop. |
| Management API | `http://127.0.0.1:8317/v8/management` (header `Authorization: Bearer <management key>`) |
| Switch events | `http://127.0.0.1:8791/events` (SSE), `http://127.0.0.1:8791/status` |
| Config | `config\config.yaml` (gitignored; template: `config\config.example.yaml`) |
| Credentials | `auths\*.json` (gitignored, secret) |
| Logs | `logs\cliproxy\`, `logs\notifier\switches.jsonl` |

## 1. Start / stop

```powershell
.\scripts\up.ps1            # first run: creates .env + config.yaml, dirs, builds, starts, prints endpoints
.\scripts\status.ps1        # compose ps + gateway probe (+ notifier)
.\scripts\down.ps1          # stop; auths\ and logs\ are kept
```

Useful switches: `up.ps1 -Pull` (newer upstream image), `-NoBuild`, `-ProxyOnly` (skip the notifier; automatic if `services\switch-notifier\Dockerfile` is missing).

On first run `up.ps1` writes `config\config.yaml` with a random **gateway key** (`access.api-keys[0]`, what T3 uses) and a random **management key**. The management key is printed **once**, because the proxy bcrypt-hashes it in the file. Save it, then:

```powershell
$env:RAHBAZ_MANAGEMENT_KEY = '<management key>'    # this session only
.\scripts\status.ps1                               # now also lists credentials per provider
```

Show your gateway key when configuring T3:

```powershell
(Select-String -Path config\config.yaml -Pattern '^\s*-\s*"?(rbgw-[0-9a-f]+)' ).Matches.Groups[1].Value
```

After editing `config\config.yaml`, run `docker compose restart cliproxy` (single-file bind mounts on Docker Desktop do not always see editor saves).

The stack survives `docker compose restart` and reboots (`restart: unless-stopped`) with credentials intact.

## 2. Add 3 accounts per provider

One login run adds one account. Run each script three times (once per account), signing into a different account each time.

```powershell
.\scripts\login-claude.ps1        # callback port 54545
.\scripts\login-codex.ps1         # callback port 1455
.\scripts\login-antigravity.ps1   # callback port 51121
```

Each script runs, inside the container:

```powershell
docker compose exec cliproxy /CLIProxyAPI/CLIProxyAPI --claude-login --no-browser
# --codex-login / --antigravity-login for the others
```

Per login:

1. The CLI prints a URL. Open it in your **Windows** browser (the container cannot open one).
2. Sign in with the account to add and approve access. Use a private window or sign out first if the browser keeps auto-selecting the previous account.
3. The provider redirects to `http://localhost:<callback port>/...`. Docker publishes that port to the container, so the login completes and a new `auths\*.json` is written.
4. The script lists new files in `auths\`. Check the pool:

```powershell
.\scripts\status.ps1 -ManagementKey $env:RAHBAZ_MANAGEMENT_KEY
# expected after all logins:  claude total=3, codex total=3, antigravity total=3
```

If a new account is missing, `docker compose restart cliproxy` (or pass `-RestartAfter` to the login script). Re-logging into an account that already exists overwrites its file rather than adding a second one, so three distinct accounts means three distinct sign-ins.

Alternative (management API, browser-driven): `GET /v8/management/oauth/auth-url?provider=claude|codex|antigravity` returns `{status,url,state}`; poll `GET /oauth/status?state=<state>`.

## 3. Drain an account (weight = 0)

Draining stops new traffic going to an account without deleting its login. `routing.strategy` is `weighted-round-robin`; credentials with weight `0` (or negative) are excluded.

**Option A: edit the credential file** (per-OAuth-account weight, integer, default 1, max 1,000,000):

1. Open `auths\<account>.json` in an editor and add or change a top-level field: `"weight": 0`. Keep the JSON valid; do not touch token fields.
2. Wait a few seconds for the hot-reload; if the change is not picked up, `docker compose restart cliproxy`.
3. To restore, set it back to `1` (or delete the field).

Sessions already bound to that credential move off it on their next quota/auth-class rebind; new sessions will not pick it.

**Option B: disable via management API** (documented upstream, reversible):

```powershell
$h = @{ Authorization = "Bearer $env:RAHBAZ_MANAGEMENT_KEY" }
$base = 'http://127.0.0.1:8317/v8/management'

# list: name, provider, status, disabled
(Invoke-RestMethod -Headers $h "$base/credentials").files | Format-Table name, provider, status, disabled

# drain
Invoke-RestMethod -Method Patch -Headers $h -ContentType 'application/json' `
  -Body '{"name":"<file name from list>","disabled":true}' "$base/credentials/status"

# restore
Invoke-RestMethod -Method Patch -Headers $h -ContentType 'application/json' `
  -Body '{"name":"<file name from list>","disabled":false}' "$base/credentials/status"
```

Upstream documents no dedicated weight endpoint for OAuth files, so use Option A for weights other than drain and Option B when you want the API.

Typical use: an account hit a weekly limit, so set weight `0` until the window resets, then restore.

## 4. Read switch events

`switch-notifier` emits `switch.quota`, `switch.error`, `switch.auth` (and later `switch.manual`) with `{from, to, provider, reason, requestId}`.

```powershell
# live stream (use curl.exe; plain `curl` is an Invoke-WebRequest alias in Windows PowerShell)
curl.exe -N http://127.0.0.1:8791/events

# current state
Invoke-RestMethod http://127.0.0.1:8791/status

# audit trail (JSON Lines)
Get-Content logs\notifier\switches.jsonl -Tail 20 -Wait | ForEach-Object { $_ | ConvertFrom-Json }
```

How a switch looks to the client:

- **Before the first token:** RahBaz retries on the next credential (`bootstrap-retries`, Codex `stream-bootstrap-buffering`). The turn succeeds; you only see the event.
- **After tokens started:** the stream cannot be moved to another account. The turn ends with an error; retry and it runs on the rebound credential. The event is still emitted.

Proxy-side logs: `docker compose logs -f cliproxy` or `logs\cliproxy\`.

If `/events` does not respond, the notifier is not running (`status.ps1` shows it). The gateway keeps working without it.

## 5. Back up `auths\`

Credential files are refresh tokens; anyone holding them can use your accounts. Encrypt backups and store them off this machine's shared folders. Never commit them.

```powershell
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
New-Item -ItemType Directory -Force -Path "$HOME\rahbaz-backups" | Out-Null
Compress-Archive -Path auths\*.json, config\config.yaml, .env -DestinationPath "$HOME\rahbaz-backups\rahbaz-$stamp.zip"
```

Zip alone is not encryption: put the archive in an encrypted location (BitLocker volume, EFS folder: `cipher /e "$HOME\rahbaz-backups"`, or a password manager vault).

Restore:

```powershell
.\scripts\down.ps1
Expand-Archive "$HOME\rahbaz-backups\rahbaz-<stamp>.zip" -DestinationPath . -Force
.\scripts\up.ps1
```

`config\config.yaml` holds your gateway key and the hashed management key; `.env` is non-secret but handy to keep.

## 6. Troubleshooting OAuth on Windows Docker

Diagnose first:

```powershell
.\scripts\status.ps1
docker compose ps                       # ports must show 127.0.0.1:54545->54545 etc.
docker compose logs --tail 100 cliproxy
```

| Symptom | Cause / fix |
|---|---|
| `Docker daemon is not reachable` | Start Docker Desktop and wait for "Engine running". |
| `service 'cliproxy' is not running` | `.\scripts\up.ps1`; check `docker compose logs cliproxy` for config errors. |
| Container exits at start, `config.yaml` is a **directory** | The file was missing when Docker first started and it created a folder. `down`, delete `config\config.yaml\`, rerun `up.ps1`. |
| Browser: "connection refused" / page cannot be reached after approving | Callback port not reachable. (1) Is the container up, with the port published (`docker compose ps`)? (2) Replace `localhost` with `127.0.0.1` in the redirect URL. (3) Another program owns the port: `netstat -ano \| findstr :54545` (or `:1455`, `:51121`). Close it (the native Codex CLI login uses 1455). (4) Windows can reserve ports: `netsh interface ipv4 show excludedportrange protocol=tcp`. If a callback port falls in a range, Docker cannot publish it. Restart the Windows NAT service (`net stop winnat; net start winnat`, admin) and bring the stack back up. |
| Redirect page loads but login does not finish | The CLI listens on the callback only while it is running; do not close the terminal before approving. Login URLs expire quickly, so rerun the script and be fast. If the CLI offers to paste the redirect URL, paste the full URL from the address bar. |
| `the input device is not a TTY` | Run the script from a normal interactive PowerShell/Windows Terminal window, not a piped or CI context. |
| Login succeeded but account is not in `status.ps1` | `docker compose restart cliproxy` (bind-mount file events can be missed). Confirm the file exists: `Get-ChildItem auths`. |
| Wrong account got added / same account twice | The browser reused its signed-in session. Sign out first or use a private window; one account yields one file. |
| Provider says "access denied", unsupported region, or a risk/captcha page | Provider-side. Try again from a normal browser profile; disable VPN/proxy for the login; do not mass-add accounts in one sitting. |
| Antigravity login hangs | Make sure nothing else is on 51121; complete the Google consent in the same browser session that opened the URL. |
| Login worked, then requests return `401` from the gateway | The T3 client is using the wrong key. It needs the `access.api-keys` value, not a provider token. Check `status.ps1` (`/v1/models` should be 200). |
| Container shows `unhealthy` but the API works | The healthcheck probes `GET /` with bash `/dev/tcp` (the upstream image is Debian and has no `wget`/`curl`; `/v1/models` would 401 without the key). If you changed `compose.yaml`, keep it that way. Inspect with `docker inspect rahbaz-cliproxy --format '{{json .State.Health}}'`. |
| Files edited on the host do not take effect | `docker compose restart cliproxy`. Editors that replace the file (new inode) leave the container on a stale copy of a single-file mount. |
| Everything is stuck | `.\scripts\down.ps1; .\scripts\up.ps1`. Your `auths\` is untouched. |

If upstream changes its config layout or flags, use `.\scripts\pull-upstream-config.ps1` to fetch the current reference and compare.
