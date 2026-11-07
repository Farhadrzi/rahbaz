# RahBaz Hub

Local OpenRouter-style gateway. The Hub owns every provider account, the model catalog, routing weights, and failover. **Clients never log into Claude / Codex / Google directly** — they only talk to this Hub.

Primary runtime: **Windows + Docker Desktop**.

## What you get

| Endpoint | Purpose |
|---|---|
| `http://127.0.0.1:8317` | Gateway API (Claude-compatible base URL) |
| `http://127.0.0.1:8317/v1` | OpenAI / Codex-compatible base URL |
| `http://127.0.0.1:8317/v1/models` | Unified model catalog |
| `http://127.0.0.1:8317/management.html` | Hub dashboard (management key) |
| `http://127.0.0.1:8791/events` | Optional switch-notifier SSE stream |
| `http://127.0.0.1:8791/status` | Optional switch-notifier status |

All Hub ports are published on **loopback only** (`127.0.0.1`).

## Prerequisites

1. [Docker Desktop](https://www.docker.com/products/docker-desktop/) for Windows (Engine running)
2. PowerShell 5.1+ (Windows Terminal recommended)
3. This repository checked out locally

No cloud API keys are required in the repo. OAuth logins create credential files under `auths/` (gitignored).

## Quick start

From the repository root:

```powershell
.\scripts\up.ps1
```

First run will:

- Create `.env` from `.env.example` (non-secret image/path defaults)
- Create `config/config.yaml` from `config/config.example.yaml` with **random** gateway and management keys
- Create `auths/`, `logs/`, and `plugins/` directories
- Build/start `cliproxy` + `switch-notifier`

Then add accounts (one login = one account; repeat per account):

```powershell
.\scripts\login-claude.ps1        # OAuth callback :54545
.\scripts\login-codex.ps1         # OAuth callback :1455
.\scripts\login-antigravity.ps1   # OAuth callback :51121
```

Each script prints a URL. Open it in your **Windows** browser, approve access, and wait for the callback to complete in the terminal.

Verify:

```powershell
.\scripts\status.ps1
.\scripts\list-models.ps1
```

Stop (credentials and logs are kept):

```powershell
.\scripts\down.ps1
```

## Keys (never commit these)

| Key | Used by | Where it lives |
|---|---|---|
| Gateway API key (`access.api-keys[0]`) | RahBaz Client / any OpenAI-compatible client | `config/config.yaml` (gitignored) |
| Management key | Hub dashboard + management API | Printed **once** on first `up.ps1`; then bcrypt-hashed in config |

Show the gateway key locally when configuring a client:

```powershell
(Select-String -Path config\config.yaml -Pattern '^\s*-\s*"?(rbgw-[0-9a-f]+)' ).Matches.Groups[1].Value
```

For management API / richer `status.ps1` output in the current shell:

```powershell
$env:RAHBAZ_MANAGEMENT_KEY = '<management key you saved>'
.\scripts\status.ps1
```

Placeholder values in `config/config.example.yaml` (`change-me-*`) are **not** real secrets. Live `config/config.yaml`, `.env`, and `auths/*.json` must stay out of Git.

## Pointing a client at the Hub only

| Client setting | Value |
|---|---|
| Hub / base URL | `http://127.0.0.1:8317` (or `.../v1` for OpenAI-shaped clients) |
| API key | Hub gateway key only |

- **RahBaz Client** (recommended): single provider named RahBaz — see [../client/README.md](../client/README.md).
- Stock T3 Code can be pointed at the Hub as a fallback — see [../T3_CLIENT_SETUP.md](../T3_CLIENT_SETUP.md). That is not the primary product path.

Do not paste provider OAuth tokens into any client. Those stay in Hub `auths/`.

## Ports reference

| Host port | Role |
|---|---|
| `8317` | Gateway + management UI |
| `8085` | Management helpers |
| `1455` | Codex OAuth callback |
| `54545` | Claude OAuth callback |
| `51121` | Antigravity / extra OAuth callbacks |
| `11451` | Extra upstream helper |
| `8791` | switch-notifier |

## Day-2 operations

Weight drain, backups, OAuth troubleshooting, and switch-event reading are documented in [../OPERATOR_RUNBOOK.md](../OPERATOR_RUNBOOK.md).

Useful script flags:

- `.\scripts\up.ps1 -Pull` — pull a newer upstream proxy image
- `.\scripts\up.ps1 -NoBuild` — skip rebuilding the notifier image
- `.\scripts\up.ps1 -ProxyOnly` — start only `cliproxy`

After editing `config/config.yaml`, run `docker compose restart cliproxy` (Docker Desktop single-file bind mounts do not always pick up editor saves).

## Source layout (this repo)

**Boundary:** Hub and Client are separate **products**. Same git tree is OK while developing; split repos later. Client installer must never install Hub — users set Hub up themselves, then only enter URL + API key in the Client. See [../PRODUCT_BOUNDARY.md](../PRODUCT_BOUNDARY.md).

This repository is **Hub-focused**. Publishable Hub pieces:

- `compose.yaml`
- `config/config.example.yaml`
- `scripts/` (start / login / status helpers)
- `services/switch-notifier/`
- `docs/`

The nested checkout `clients/rahbaz-client/` is **gitignored** today (large T3 fork). Client installers/source publishing strategy is separate — see [../client/README.md](../client/README.md) and the root README “Publishing layout” note.
