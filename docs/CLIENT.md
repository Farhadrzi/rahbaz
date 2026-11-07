# RahBaz Client

T3 Code fork that speaks **only** to RahBaz Hub (local OpenRouter).

## Location

`clients/rahbaz-client/` — MIT fork of https://github.com/pingdotgg/t3code with attribution retained.

## User experience

1. Start Hub: `.\scripts\up.ps1`
2. Log accounts into Hub (not into the Client)
3. Start RahBaz Client
4. Settings show a single provider: **RahBaz**
5. Model picker lists whatever Hub returns from `/v1/models`
6. Chats go Client → Hub → pooled upstream accounts

## Provider settings

| Field | Default |
|---|---|
| Hub base URL | `http://127.0.0.1:8317` |
| Gateway API key | from Hub `config/config.yaml` → `access.api-keys[0]` |

No Claude / Codex / Google sign-in screens for daily use.

## Build (Windows)

See [clients/rahbaz-client/README.rahbaz.md](../clients/rahbaz-client/README.rahbaz.md). Upstream build uses Vite+ (`vp`). OpenCode CLI must be on PATH.

For a **standalone desktop installer** (not the browser), see [DESKTOP.md](DESKTOP.md) and run `.\scripts\build-desktop-win.ps1`.

## What was patched in the fork

- Only `OpenCodeDriver` registered in `apps/server/src/provider/builtInDrivers.ts`
- Only RahBaz entry in `packages/client-runtime/src/providerClients.ts`
- Hub URL + API key settings; `OPENCODE_CONFIG_CONTENT` generated from Hub `/v1/models`
- Default enabled instance: `opencode` (UI label **RahBaz**)

## Why OpenCode under the hood

T3 is an agent harness: drivers wrap coding CLIs. The RahBaz driver uses OpenCode as the single engine, configured with an OpenAI-compatible provider pointing at the Hub, so the picker can include **all** Hub models (not only Anthropic-shaped ones).

## Troubleshooting: picker shows OpenCode models, not Hub

1. In Client → Settings → Providers → **RahBaz**, set **Hub API key** to Hub `access.api-keys[0]` (Sensitive). Without this key the Client cannot read `/v1/models`.
2. Fully restart the Client (stop `vp run` / desktop app, start again) so OpenCode reloads `OPENCODE_CONFIG_CONTENT` with `enabled_providers: ["rahbaz"]`.
3. Confirm Hub catalog: `.\scripts\list-models.ps1` (should list your 26+ models).
4. Hub dashboard (accounts/models): open `http://127.0.0.1:8317/management.html` and enter the **management** key.
