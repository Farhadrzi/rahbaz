# RahBaz Desktop Apps

Standalone Electron apps built from the RahBaz Client (T3 fork). Same product as the browser UI: one RahBaz provider → Hub at `http://127.0.0.1:8317`.

## Prerequisites (all platforms)

1. Hub running: `.\scripts\up.ps1` (accounts already logged in)
2. OpenCode CLI on PATH is preferred; if missing, RahBaz Client installs a pinned official release under `~/.rahbaz/tools/opencode`
3. Client deps installed: in `clients/rahbaz-client`, activate Vite+ then `vp i`
4. Node **26.12.1** (matches monorepo engines)

## Windows (this machine)

Installer produced at:

`release/desktop/win/RahBaz-<version>-x64.exe`

### Build again

```powershell
cd C:\Users\farha\.t3\projects\rahbaz
.\scripts\build-desktop-win.ps1
```

### Toolchain notes (Windows)

- **Rust** (`rustup` + `x86_64-pc-windows-msvc`)
- **Python 3** (for node-gyp)
- **MSVC linker** from VS 2019/2022 Build Tools (`VC\Tools\MSVC\...\bin\Hostx64\x64\link.exe`)
- **Windows SDK libs/headers** — if the official SDK is not installed (UAC blocked), use a portable splat via [xwin](https://github.com/Jake-Shadle/xwin) and set before building:

```powershell
$msvc = 'C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.29.30133'
$env:Path = "$msvc\bin\Hostx64\x64;$env:Path"
$env:INCLUDE = "$msvc\include;F:\xwin\crt\include;F:\xwin\sdk\include\ucrt;F:\xwin\sdk\include\um;F:\xwin\sdk\include\shared"
$env:LIB = "$msvc\lib\x64;F:\xwin\crt\lib\x86_64;F:\xwin\sdk\lib\um\x86_64;F:\xwin\sdk\lib\ucrt\x86_64"
$env:T3CODE_DESKTOP_REUSE_RESOURCE_MONITOR = 'true'  # after one successful cargo build of native/resource-monitor
$env:TEMP = 'F:\temp'; $env:TMP = 'F:\temp'         # optional if C: is tight
.\scripts\build-desktop-win.ps1
```

Ideal path (when UAC works): install VS Build Tools with **Desktop development with C++**, Windows SDK, and Spectre-mitigated libs, then build without the xwin workaround.

Unsigned NSIS is fine for local use. Artifact name: `RahBaz-<version>-x64.exe`.

## Linux (WSL2 Ubuntu)

This machine has **Ubuntu-24.04** in WSL2. Helper script installs deps, copies sources onto the Linux filesystem (avoids Windows `node_modules`), and builds an AppImage:

```powershell
wsl -d Ubuntu-24.04 -- bash /mnt/c/Users/farha/.t3/projects/rahbaz/scripts/_wsl-linux-desktop-build.sh
```

Or from inside WSL after deps exist:

```bash
cd /mnt/c/Users/farha/.t3/projects/rahbaz
bash scripts/build-desktop-linux.sh
```

Artifacts (this machine):

- `release/desktop/linux/RahBaz-0.1.7-x86_64.AppImage`
- `release/desktop/linux/RahBaz-0.1.7-amd64.deb`

Docker Desktop’s WSL distro alone is **not** enough — you need a real Linux distro (Ubuntu) for AppImage tooling.

## macOS

Must run on a Mac (no cross-compile from Windows for DMG here):

```bash
cd /path/to/rahbaz
bash scripts/build-desktop-mac.sh
# Intel: ARCH=x64 bash scripts/build-desktop-mac.sh
```

Needs Xcode CLT + Rust targets (`aarch64-apple-darwin` / `x86_64-apple-darwin`). Output: `release/desktop/mac/`.

## After install

1. Start Hub (`scripts/up.ps1`) if not already running  
2. Open RahBaz desktop app  
3. Settings → Providers → RahBaz → Hub URL + gateway API key (`rbgw-…`)  
4. Restart the app once so OpenCode reloads Hub models  

## Side-by-side with T3 Code

Full matrix: [CLIENT_IDENTITY.md](CLIENT_IDENTITY.md).

RahBaz is isolated from T3 Code:

| Concern | RahBaz | T3 Code |
| --- | --- | --- |
| Data home | `~/.rahbaz` (`RAHBAZ_HOME` or `T3CODE_HOME`) | `~/.t3` |
| App id / AUMID | `com.rahbaz.client` | `com.t3tools.t3code` |
| Protocol | `rahbaz://` | `t3code://` |
| Windows exe / shortcuts | `RahBaz` | `T3 Code …` |
| Electron userData | `%APPDATA%/rahbaz` | `%APPDATA%/t3code-v2` |
| Updater feed | `Farhadrzi/rahbaz` | `pingdotgg/t3code` |

Windows NSIS allows choosing the install directory (`oneClick: false`).

## Notes

- `--signed` needs platform certificates; omit for personal builds  
- OpenCode config/data for RahBaz is isolated under `~/.rahbaz/opencode/`  
- Branding: app id `com.rahbaz.client`, product name **RahBaz**, icons from `assets/rahbaz/` (SVG source `assets/icon.svg`)  
- Regenerate packaging icons: `node clients/rahbaz-client/scripts/generate-rahbaz-icons.mjs` (needs `sharp` + `png-to-ico`, or ImageMagick)
