# RahBaz Execution Plan

## Principles

- Prefer upstream CLIProxyAPI via Docker image; fork only when necessary.
- Keep secrets out of git.
- Windows + Docker Desktop is the primary runtime.
- RahBaz Hub = OpenRouter-style gateway; RahBaz Client = T3 fork with one provider.

## Status summary (2026-11-07)

| Area | Status |
|---|---|
| Hub Docker stack | Done — healthy on this machine |
| Multi-account OAuth + `/v1/models` | Done — user verified 26 models |
| Switch notifier | Removed — Hub is cliproxy-only |
| RahBaz Client (single Hub provider) | Done — separate repo Farhadrzi/rahbaz-client |
| OpenCode Hub config (`ConfigInvalidError` fix) | Done — legacy `provider` + allowlist |
| Windows standalone app | Done — `release/desktop/win/RahBaz-0.1.7-x64.exe` |
| Linux standalone | Done — AppImage + deb via Ubuntu-24.04 WSL |
| macOS standalone | Scripts + docs ready; build on a Mac (`scripts/build-desktop-mac.sh`) |
| Dynamic auto-weight from live quotas | Future |
| Custom RahBaz icons (replace T3 assets) | Future |

## Phase checklist

### Hub

- [x] Research / spec / architecture
- [x] Compose + config v8 + login scripts
- [x] Management dashboard (`/management.html`, `allow-remote` for Docker Desktop)
- [x] `list-models.ps1`

### Client

- [x] T3 shallow clone → `clients/rahbaz-client`
- [x] Only RahBaz/OpenCode provider registered
- [x] Hub URL + API key → `/v1/models` → OpenCode config
- [x] Browser Client E2E (user confirmed)

### Desktop

- [x] Branding: productName RahBaz, appId `com.rahbaz.client`, `~/.rahbaz` data home, Farhadrzi/rahbaz updater, RahBaz icons
- [x] Build scripts: win / linux / mac + [DESKTOP.md](DESKTOP.md)
- [x] Windows NSIS artifact produced on this machine
- [x] Linux AppImage (+ deb) via WSL Ubuntu-24.04
- [ ] macOS DMG (Mac only)

## Definition of done (product goal)

1. [x] One Hub manages all accounts/models (OpenRouter-style)
2. [x] One Client talks only to that Hub
3. [x] Priority/failover owned by Hub
4. [x] Standalone Win + Linux apps installable; macOS build script ready for a Mac
