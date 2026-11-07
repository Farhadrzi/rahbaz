# RahBaz Client ↔ T3 Code identity matrix

Goal: install and run both side-by-side with zero shared state or OS registration collisions.

| Concern | RahBaz | T3 Code |
| --- | --- | --- |
| Product name | RahBaz | T3 Code |
| App id / AUMID | `com.rahbaz.client` | `com.t3tools.t3code` |
| Dev AUMID | `com.rahbaz.client.dev` | `com.t3tools.t3code.dev` |
| Protocol | `rahbaz://` / `rahbaz-dev://` | `t3code://` / `t3code-dev://` |
| Linux executable / WMClass | `rahbaz` | `t3code` |
| Linux desktop entry | `com.rahbaz.Client.desktop` | `com.t3tools.T3Code.desktop` |
| Linux metainfo | `com.rahbaz.client.metainfo.xml` | `com.t3tools.t3code.metainfo.xml` |
| Data home | `~/.rahbaz` | `~/.t3` |
| Home env | `RAHBAZ_HOME` (preferred) or `T3CODE_HOME` | `T3CODE_HOME` |
| Electron userData | `%APPDATA%/rahbaz` | `%APPDATA%/t3code-v2` |
| Windows NSIS | custom dir allowed; shortcut/uninstall **RahBaz** | T3 Code installer |
| Updater GitHub repo | `Farhadrzi/rahbaz` (`T3CODE_DESKTOP_UPDATE_REPOSITORY`) | `pingdotgg/t3code` |
| OpenCode config/data | `~/.rahbaz/opencode/*` | shared OpenCode defaults |
| OpenCode binary fallback | `~/.rahbaz/tools/opencode/bin` (pinned) | PATH / `~/.opencode` |
| Icons | `assets/rahbaz/*` from `assets/icon.svg` | upstream T3 assets |

## Verify side-by-side

1. Install T3 Code and RahBaz to different directories (Windows NSIS lets you pick).
2. Leave `T3CODE_HOME` / `RAHBAZ_HOME` unset for normal desktop launches.
3. Confirm `~/.t3` and `~/.rahbaz` both exist after each app has launched once.
4. Confirm Start Menu / dock entries and protocol handlers do not overwrite each other.
5. Confirm RahBaz Settings → Providers still talks only to Hub `http://127.0.0.1:8317`.

## Remaining blockers

- **Code signing**: unsigned Windows/macOS builds still show SmartScreen / Gatekeeper warnings; unrelated to T3 collision.
- **GitHub releases**: updater expects `Farhadrzi/rahbaz` release assets; publish before relying on auto-update.
- **Ambient `T3CODE_HOME`**: if a shell exports `T3CODE_HOME=~/.t3` for T3 CLI work, set `RAHBAZ_HOME=~/.rahbaz` when launching RahBaz (preferred override).
- Some internal telemetry/service labels may still say `t3code` in logs; they do not affect OS install identity.
