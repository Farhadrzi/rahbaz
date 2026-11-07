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

> **Boundary:** Hub setup is **your** job. The Client installer does **not** install Hub/Docker. It only installs the app + connection deps (OpenCode). Same git tree is OK while developing; split into separate repos later. See [../PRODUCT_BOUNDARY.md](../PRODUCT_BOUNDARY.md).

## Prerequisites (end user)

1. **RahBaz Hub** already running (user responsibility) — [../hub/README.md](../hub/README.md)
2. At least one Hub provider account logged in on the Hub
3. Hub gateway API key (from Hub `config/config.yaml` → `access.api-keys[0]`)

You do **not** need to pre-install OpenCode. The Client discovers PATH OpenCode or installs a pinned copy under `~/.rahbaz/tools/opencode`.

## Install (end users)

When release artifacts are published:

| Platform | Typical artifact |
|---|---|
| Windows | `RahBaz-<version>-x64.exe` (NSIS; choose install folder) |
| Linux | `RahBaz-<version>-x86_64.AppImage` and/or `.deb` |
| macOS | `RahBaz-<version>-arm64.dmg` (or x64) |

1. Set up and start **Hub** yourself (not part of this installer).
2. Install / open **RahBaz Client** (installer does not touch Hub).
3. Settings → Providers → **RahBaz** — enter only:
   - Hub URL: `http://127.0.0.1:8317` (default)
   - Hub API key: gateway key (Sensitive)
4. Client connects automatically: ensures OpenCode, loads Hub `/v1/models`, ready to chat.

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

### Publishing strategy

- **Now:** Hub is published from this repo; Client source may stay local/gitignored in the same working tree.
- **End state:** separate Client repository; Hub and Client installers stay separate forever.
- Client installer must never embed Hub/Docker. Desktop CI builds Client artifacts only.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Model picker empty / wrong models | Confirm Hub `.\scripts\list-models.ps1`; set Hub API key; fully restart Client |
| `401` from Hub | Client is using the wrong key — use gateway `access.api-keys`, not a provider token |
| Hub unreachable | Start Hub (`.\scripts\up.ps1`); confirm `http://127.0.0.1:8317` |
| OpenCode models instead of Hub catalog | Restart after setting Hub key so `OPENCODE_CONFIG_CONTENT` reloads with provider `rahbaz` only |

More operator detail: [../CLIENT.md](../CLIENT.md) (implementation notes) and [../hub/README.md](../hub/README.md).
