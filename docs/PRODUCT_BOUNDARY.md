# RahBaz product boundary

## Same repo now, separate later

During development it is fine for Hub and Client source to live in one working tree / one git repo. **At the end** they should be published as separate repositories. Until then, treat them as two products that happen to share a folder.

## Runtime rule (hard)

| Product | What it is | What it is not |
|---|---|---|
| **RahBaz Hub** | Local multi-account gateway (Docker / CLIProxyAPI). User installs and operates it. | Not bundled inside the Client installer |
| **RahBaz Client** | Desktop app. Installs everything needed to **connect** to a Hub the user already runs. | Does not install Docker, Compose, or Hub OAuth |

## Client installer responsibilities

The Client installer / first launch **must**:

- Install the RahBaz desktop app with its own identity (`com.rahbaz.client`, `~/.rahbaz`, `rahbaz://`)
- Ensure connection runtime deps (today: OpenCode binary + isolated OpenCode config under `~/.rahbaz`)
- Offer settings for **Hub URL** and **Hub gateway API key** only (for normal users)

The Client installer **must not**:

- Install or start RahBaz Hub / Docker Desktop / Compose
- Perform provider OAuth logins (Claude / Codex / Antigravity / …) — those stay on the Hub
- Require the user to configure OpenCode manually when auto-detect/install works

## User journey

1. User sets up Hub (their responsibility): `scripts/up.ps1`, provider logins, note gateway API key.
2. User installs RahBaz Client.
3. User enters Hub URL (default `http://127.0.0.1:8317`) + gateway API key.
4. Client discovers/installs OpenCode if needed, loads Hub `/v1/models`, and chats work.

## Contract between them

HTTP only: Client → Hub (`/v1/*` with gateway key; optional management key later for usage UI). No shared process, no shared data directory, no shared installer.
