# RahBaz Client

Desktop / browser client that talks **only** to RahBaz Hub. It is an MIT fork of [T3 Code](https://github.com/pingdotgg/t3code) with a single provider: **RahBaz**.

Stock Claude, Codex, Cursor, Antigravity, and other direct providers are not registered for daily use. Account OAuth lives in the Hub.

## Intended product identity

| Item | Value |
|---|---|
| App ID / bundle ID | `com.rahbaz.client` |
| Product name | RahBaz |
| Protocol scheme | `rahbaz://` |
| User data home (target) | `~/.rahbaz` (platform equivalents under AppData / Application Support) |
| Updater feed | GitHub releases on [`Farhadrzi/rahbaz`](https://github.com/Farhadrzi/rahbaz) |
| Artifact name pattern | `RahBaz-<version>-<arch>.<ext>` |

These identifiers are chosen so RahBaz can sit **side-by-side with T3 Code** without sharing install paths, shortcuts, protocol handlers, or updater metadata.

> **Status:** Hub docs live in the Hub repo. Full Client source stays a local/gitignored checkout (`clients/rahbaz-client/`) until it moves to its **own** repository. Hub and Client must not be mixed in one publishable tree.

## Prerequisites

1. **RahBaz Hub** running and reachable at `http://127.0.0.1:8317` — see [../hub/README.md](../hub/README.md)
2. At least one Hub account logged in (`scripts/login-*.ps1` from the Hub repo)
3. **OpenCode CLI** available at runtime (current desktop builds still invoke OpenCode under the hood)
4. For building from source: Node (monorepo engines), Vite+ (`vp`), platform toolchains — see [../DESKTOP.md](../DESKTOP.md)

## Install (end users)

When release artifacts are published to `Farhadrzi/rahbaz`:

| Platform | Typical artifact |
|---|---|
| Windows | `RahBaz-<version>-x64.exe` (NSIS) |
| Linux | `RahBaz-<version>-x86_64.AppImage` and/or `.deb` |
| macOS | `RahBaz-<version>-arm64.dmg` (or x64) |

1. Start the Hub first.
2. Install / open RahBaz Client.
3. Settings → Providers → **RahBaz**:
   - Hub URL: `http://127.0.0.1:8317`
   - Hub API key: gateway key from Hub `config/config.yaml` → `access.api-keys[0]` (Sensitive)
4. Restart the Client once so the model picker reloads Hub `/v1/models`.

Never paste provider OAuth tokens into the Client.

## Update

- Desktop builds are intended to use **electron-updater** against GitHub releases on `Farhadrzi/rahbaz`.
- Release jobs must upload per-platform installers **and** updater metadata (`latest*.yml` / platform equivalents) that match electron-updater expectations.
- Unsigned personal builds will show OS trust warnings; signed releases need owner-supplied certificates (not required for local Hub development).

Until CI publishes signed releases, update by downloading a newer installer from Releases or rebuilding from source.

## Side-by-side with T3 Code

Safe coexistence checklist (verify before claiming “fully separate”):

| Area | RahBaz expectation | Avoid colliding with T3 |
|---|---|---|
| App ID | `com.rahbaz.client` | Do not reuse T3 bundle / AppUserModel IDs |
| Protocol | `rahbaz://` | Do not register T3’s scheme |
| Data directory | `~/.rahbaz` (and Electron `userData` under RahBaz name) | Do not write into T3’s userData |
| Shortcuts / Start Menu | Product name **RahBaz** | Distinct uninstall key / Start Menu folder |
| Updater | `Farhadrzi/rahbaz` | Do not point at upstream T3 release feeds |
| OpenCode config | Prefer a RahBaz-isolated config/home | Do not overwrite the user’s global OpenCode config silently |

You can keep stock T3 installed for other work. For RahBaz daily use, prefer this Client over pointing stock T3 at the Hub ([legacy notes](../T3_CLIENT_SETUP.md)).

## Build from source (maintainers)

The nested tree `clients/rahbaz-client/` is **ignored by the root `.gitignore`**. Local bootstrap:

```powershell
.\scripts\bootstrap-rahbaz-client.ps1 -CloneIfMissing
# apply / retain RahBaz single-provider patches, then:
.\scripts\build-desktop-win.ps1
```

Linux / macOS helpers: `scripts/build-desktop-linux.sh`, `scripts/build-desktop-mac.sh` (macOS must run on a Mac). Details: [../DESKTOP.md](../DESKTOP.md).

### Publishing strategy (preferred)

**Required:** publish Client from a **separate repository**. Do not un-ignore or vendor `clients/rahbaz-client/` into the Hub repo.

Installers may be attached to Hub releases **or** published from the Client repo’s own Releases feed (document the updater URL). The Hub repo must remain Hub-only source.

The `desktop-release` workflow in the Hub repo is a **skeleton**: it may check out the separate Client repo later; it must not assume Client source is mixed into Hub.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Model picker empty / wrong models | Confirm Hub `.\scripts\list-models.ps1`; set Hub API key; fully restart Client |
| `401` from Hub | Client is using the wrong key — use gateway `access.api-keys`, not a provider token |
| Hub unreachable | Start Hub (`.\scripts\up.ps1`); confirm `http://127.0.0.1:8317` |
| OpenCode models instead of Hub catalog | Restart after setting Hub key so `OPENCODE_CONFIG_CONTENT` reloads with provider `rahbaz` only |

More operator detail: [../CLIENT.md](../CLIENT.md) (implementation notes) and [../hub/README.md](../hub/README.md).
