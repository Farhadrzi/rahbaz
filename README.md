# RahBaz

Local **OpenRouter-style** AI stack: one Hub for every account and model, one Client that only talks to that Hub.

| Piece | Role |
|---|---|
| **RahBaz Hub** | Multi-account gateway (CLIProxyAPI). OAuth pools, quotas, failover, `/v1/models` catalog, priority/weights. |
| **RahBaz Client** | T3 Code fork. Single provider named `RahBaz`. Model picker = Hub catalog. No direct Claude/Codex/Google login for daily use. |

You adjust account order and model priority in the **Hub**. The Client just works.

## Quick start — Hub (Windows + Docker Desktop)

```powershell
.\scripts\up.ps1
.\scripts\login-claude.ps1       # repeat per account
.\scripts\login-codex.ps1
.\scripts\login-antigravity.ps1
.\scripts\list-models.ps1        # OpenRouter-style catalog from the Hub
```

| | |
|---|---|
| Hub API | `http://127.0.0.1:8317` |
| Models | `http://127.0.0.1:8317/v1/models` |
| Dashboard | `http://127.0.0.1:8317/management.html` (management key) |

Full Hub guide: **[docs/hub/README.md](docs/hub/README.md)**  
Day-2 ops: **[docs/OPERATOR_RUNBOOK.md](docs/OPERATOR_RUNBOOK.md)**

## RahBaz Client (overview)

Install or build the Client, point it at the Hub only:

- Hub URL: `http://127.0.0.1:8317`
- API key: Hub gateway key (`access.api-keys[0]` in local `config/config.yaml` — never commit that file)

Identity targets: app id `com.rahbaz.client`, data under `~/.rahbaz`, protocol `rahbaz://`, updates from [`Farhadrzi/rahbaz`](https://github.com/Farhadrzi/rahbaz) releases.

**[docs/client/README.md](docs/client/README.md)** — install, update, side-by-side with T3  
**[docs/DESKTOP.md](docs/DESKTOP.md)** — Windows / Linux / macOS packaging notes

### Hard separation (do not mix)

**RahBaz Hub and RahBaz Client are separate products.** They must not share one mixed source tree, one installer, or one runtime identity.

| | Hub (`Farhadrzi/rahbaz`) | Client (separate repo) |
|---|---|---|
| This public GitHub repo | **Yes — Hub only** | No |
| Docker Compose / OAuth / `auths/` | Hub | Never |
| Desktop app / `~/.rahbaz` / OpenCode | Never | Client |
| Local `clients/rahbaz-client/` | Dev convenience only; **gitignored**; not published here | Will live in its own repository |

CI: Hub validation runs in this repo. Desktop release stays a **skeleton** that builds from a **separate Client repository** (checkout/dispatch), never by vendoring the Client into Hub.

## Secrets stay local

Never commit:

- `.env` (created from `.env.example`)
- `config/config.yaml` (created from `config/config.example.yaml`)
- `auths/*.json` (OAuth refresh tokens)
- `logs/`, `release/`, `.handoff/`

Templates and examples use placeholders only (`change-me-*`).

## Docs map

| Doc | Purpose |
|---|---|
| [docs/hub/README.md](docs/hub/README.md) | Hub setup (Docker Desktop first) |
| [docs/client/README.md](docs/client/README.md) | Client install / update / T3 coexistence |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Hub + Client design |
| [docs/SPEC.md](docs/SPEC.md) | Product requirements |
| [docs/OPERATOR_RUNBOOK.md](docs/OPERATOR_RUNBOOK.md) | Day-2 Hub operations |
| [docs/CLIENT.md](docs/CLIENT.md) | Client implementation notes |
| [docs/DESKTOP.md](docs/DESKTOP.md) | Standalone app build notes |
| [docs/T3_CLIENT_SETUP.md](docs/T3_CLIENT_SETUP.md) | Legacy: stock T3 → Hub |

## Design in one sentence

RahBaz Hub is your private OpenRouter; RahBaz Client is the only app that talks to it.
