# RahBaz Research Notes

Date: 2026-11-07  
Repo: `rahbaz`  
Upstream inspiration: [router-for-me/CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) (MIT)

## Problem

You own multiple non-API subscription accounts across providers (Claude ×3, Codex ×3, Antigravity ×3, plus others). You want T3 Code clients to talk to **one** local gateway only. That gateway owns:

- OAuth / login for every account
- Quota-aware routing and failover
- Automatic account/model switching
- Visible notifications when a switch happens (including mid-turn when possible)

You should not manually juggle which account or model is healthy.

## Upstream findings (CLIProxyAPI)

CLIProxyAPI already solves most of the hard parts:

| Capability | Upstream status |
|---|---|
| Claude / Codex / Antigravity / Grok / Muse / Devin OAuth | Supported |
| Multi-account pools + round-robin / weighted-round-robin / fill-first | Supported |
| Session affinity + auto failover on auth/quota errors | Supported |
| OpenAI / Claude / Gemini / Codex compatible endpoints | Supported |
| Docker image `eceasy/cli-proxy-api` + compose | Supported |
| Management API (`/v8/management/...`) for OAuth URLs, auth ops | Supported |
| Stream bootstrap buffering (Codex overload before first token) | Opt-in; failovers **before** headers/tokens commit |
| True mid-stream resume after tokens already sent | **Not generally possible** without client cooperation |

Key ports from upstream compose:

- `8317` — API
- `8085` — management / helper
- `1455` — Codex OAuth callback
- `54545` — Claude OAuth callback
- `51121` / `11451` — additional provider login callbacks

Auth files live in a mounted auth directory (default `./auths` → `/root/.cli-proxy-api`).

## T3 Code connection model (critical)

T3 Code does **not** call model APIs itself. It launches provider CLIs (Claude Code, Codex, Antigravity ACP, etc.) and injects **per-instance environment variables**.

Implications:

1. **Claude via RahBaz** is the cleanest path:
   - Dedicated `CLAUDE_CONFIG_DIR` (e.g. `~/.claude_rahbaz`)
   - `ANTHROPIC_BASE_URL=http://127.0.0.1:8317`
   - `ANTHROPIC_AUTH_TOKEN=<rahbaz-api-key>`
   - `ANTHROPIC_API_KEY=` (explicit empty)
   - Log out any cached Anthropic login in that config dir

2. **Codex via RahBaz**:
   - Point Codex `config.toml` `model_providers.rahbaz.base_url` at `http://127.0.0.1:8317/v1`
   - Use `env_key` / T3 env for the dummy/proxy token
   - Prefer Responses wire API

3. **Native Antigravity T3 provider** signs into Google itself and does **not** take a generic base URL override. For “T3 only talks to RahBaz”:
   - Put Antigravity subscriptions into CLIProxyAPI’s Antigravity OAuth pool
   - Consume those models through Claude/Codex/OpenAI-compatible T3 instances pointed at RahBaz
   - Do **not** enable the native Antigravity provider in day-to-day use if exclusive gateway routing is required

4. There is no first-class “OpenAI-compatible provider” in T3 yet; Claude/Codex/OpenCode env + config overrides are the supported bridge.

## Gaps vs desired product

| Desired | Gap | RahBaz approach |
|---|---|---|
| One branded gateway for T3-only use | Upstream is generic | Overlay config, presets, docs, enforcement helpers |
| Notify user when auto-switch happens | Upstream logs/management, no T3 UX hook | Deferred; Hub logs + Client retry are enough for v0.1 |
| Quota-aware automatic weight changes | Weights are manual / static | Control heuristics: cooldown, weight=0 on 429 windows, restore later |
| Mid-turn switch after tokens started | HTTP streaming already committed | Bootstrap buffering + session rebind; emit switch event; optionally restart turn with notice |
| Desktop tray for Win/Linux/Mac | EasyCLIProxyAPI exists upstream | Thin RahBaz desktop later; Windows first on this machine |
| Secrets never in chat | N/A | Docker volumes + `request_secret` / local files only |

## Decision

**Do not fork CLIProxyAPI on day one.** Vendor via official Docker image and treat RahBaz as:

1. Opinionated config + compose stack (cliproxy-only)
2. Separate RahBaz Client repo that only connects to the Hub
3. T3-only client presets as a fallback
4. Optional patch fork later if bootstrap buffering needs deeper hooks

If a source patch becomes necessary, clone into `vendor/CLIProxyAPI` and build with compose `build:`.

## References

- https://github.com/router-for-me/CLIProxyAPI
- https://help.router-for.me/introduction/quick-start
- https://github.com/pingdotgg/t3code/blob/main/docs/user/providers-claude.md
- ModelDeck guide on pooling Claude/Codex via CLIProxyAPI
