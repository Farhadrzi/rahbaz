# RahBaz product boundary

## Separate repositories

| Product | Repository |
|---|---|
| **RahBaz Hub** | https://github.com/Farhadrzi/rahbaz |
| **RahBaz Client** | https://github.com/Farhadrzi/rahbaz-client |

They must never share one installer or one runtime identity. Docs may cross-link; source and CI stay separate.

## Runtime rule

| Product | What it is | What it is not |
|---|---|---|
| **RahBaz Hub** | Local multi-account gateway (Docker / CLIProxyAPI). User installs and operates it. | Not bundled inside the Client installer |
| **RahBaz Client** | Desktop app. Installs everything needed to **connect** to a Hub the user already runs. | Does not install Docker, Compose, or Hub OAuth |

## Client installer responsibilities

The Client installer / first launch **must**:

- Install the RahBaz desktop app (`com.rahbaz.client`, `~/.rahbaz`, `rahbaz://`)
- Ensure connection runtime deps (OpenCode under `~/.rahbaz` when needed)
- Offer settings for **Hub URL** and **Hub gateway API key** only (normal users)

The Client installer **must not**:

- Install or start RahBaz Hub / Docker Desktop / Compose
- Perform provider OAuth logins (those stay on the Hub)

## User journey

1. Set up Hub (this repo): `scripts/up.ps1`, provider logins, note gateway API key.
2. Install RahBaz Client from https://github.com/Farhadrzi/rahbaz-client/releases
3. Enter Hub URL (`http://127.0.0.1:8317`) + gateway API key.
4. Client connects automatically.

## Desktop releases (Client repo)

On [rahbaz-client](https://github.com/Farhadrzi/rahbaz-client):

```bash
git tag v0.1.0
git push origin v0.1.0
```

CI builds Windows x64, Linux x64 AppImage, macOS Apple Silicon (arm64), and macOS Intel (x64), then publishes a GitHub Release. Builds are unsigned unless you add signing secrets.
