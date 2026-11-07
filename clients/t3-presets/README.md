# T3 presets

Copy-and-paste presets that point T3 Code provider instances **only** at RahBaz (`http://127.0.0.1:8317`). Full walkthrough: [docs/T3_CLIENT_SETUP.md](../../docs/T3_CLIENT_SETUP.md).

| File | Used for |
|---|---|
| `claude.env.example` | Env vars for a T3 Claude instance |
| `codex.rahbaz.toml` | Provider block for a dedicated Codex home |

## Claude

1. `New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude_rahbaz"`
2. T3 → Settings → Providers → Add Claude instance; set `CLAUDE_CONFIG_DIR` to that dir.
3. Copy the three variables from `claude.env.example` into the instance **Environment variables**:
   - `ANTHROPIC_BASE_URL=http://127.0.0.1:8317`
   - `ANTHROPIC_AUTH_TOKEN` = your RahBaz gateway key (Sensitive)
   - `ANTHROPIC_API_KEY` = empty
4. If the dir previously logged into Anthropic directly, run `/logout` once.

## Codex

1. Pick an isolated home, e.g. `~\.codex_rahbaz`.
2. Merge `codex.rahbaz.toml` into its `config.toml`.
3. In the T3 Codex instance env, set `RAHBAZ_API_KEY` (Sensitive) to your gateway key.
4. Don't sign in with ChatGPT on that instance.

## Rules

- Presets must reference `127.0.0.1:8317` and no other host.
- Never put real keys in these files; keys go in T3's Sensitive env fields.
- After editing, run `.\scripts\verify-t3-rahbaz-only.ps1`. It exits non-zero if a preset drifts.
