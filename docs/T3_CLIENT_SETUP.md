# Legacy: stock T3 → RahBaz Hub

> **Primary product path:** use **RahBaz Client** (`clients/rahbaz-client`) with a single RahBaz provider — see [CLIENT.md](CLIENT.md).  
> This page is the fallback for stock T3 Code only.

Goal: every stock T3 provider instance used for daily work talks **only** to `http://127.0.0.1:8317`. Provider OAuth lives inside the Hub, not inside T3.

## Prerequisites

1. RahBaz stack is up (`scripts/up.ps1` or `docker compose up -d`)
2. You have logged accounts into the proxy (`scripts/login-claude.ps1`, etc.)
3. You know your RahBaz gateway API key from `config/config.yaml`

## Claude instance (recommended primary)

1. Create a dedicated config dir (do not reuse your normal Claude login):

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude_rahbaz" | Out-Null
```

2. In T3 → **Settings → Providers → Add Claude instance**:
   - Name: `Claude via RahBaz`
   - Binary path: `claude`
   - CLAUDE_CONFIG_DIR path: `C:\Users\<you>\.claude_rahbaz`

3. Environment variables (not Launch arguments):

| Variable | Value |
|---|---|
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:8317` |
| `ANTHROPIC_AUTH_TOKEN` | `<rahbaz-gateway-api-key>` (Sensitive) |
| `ANTHROPIC_API_KEY` | *(explicit empty)* |

4. If that config dir previously logged into Anthropic directly, open a Claude session with that dir and run `/logout`.

5. Select models normally in T3. RahBaz routes to healthy Claude (or aliased) credentials.

## Codex instance

1. Create a dedicated Codex home if you want isolation, e.g. `~\.codex_rahbaz`.
2. Write provider block (see `clients/t3-presets/codex.rahbaz.toml`).
3. In T3 Codex provider Environment variables, set the env key referenced by `env_key` to the RahBaz gateway API key (Sensitive).
4. Do **not** use ChatGPT sign-in on that T3 Codex instance for daily work.

## Antigravity accounts

Add them to RahBaz with `scripts/login-antigravity.ps1`. Consume models through Claude/Codex T3 instances pointed at RahBaz.

Disable or ignore the native T3 Antigravity provider for day-to-day coding if you require exclusive gateway routing. Native Antigravity signs into Google itself and bypasses RahBaz.

## Other providers

- Grok / Muse / Devin / OpenAI-compatible upstreams: add via RahBaz login or `config.yaml` api-keys / openai-compatibility blocks.
- Point T3 Claude or Codex (or future OpenCode) at RahBaz the same way.

## Verification

Run:

```powershell
.\scripts\verify-t3-rahbaz-only.ps1
```

This checks that documented preset files still target loopback RahBaz and that the gateway is reachable.

## Failover

Credential rotation is handled inside the Hub gateway. Watch `docker compose logs -f cliproxy` or `logs\cliproxy\` if you need operator visibility; the Client only needs Hub URL + gateway API key.
