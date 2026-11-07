#!/bin/bash
# Resume Linux AppImage build after deps are already installed in ~/rahbaz-linux-build.
set -euo pipefail
export PATH="$HOME/.local/node-v26.12.1-linux-x64/bin:$HOME/.cargo/bin:$PATH"
# shellcheck disable=SC1091
source "$HOME/.cargo/env" 2>/dev/null || true

node -v
cargo --version

CLIENT="$HOME/rahbaz-linux-build/clients/rahbaz-client"
OUT="/mnt/c/Users/farha/.t3/projects/rahbaz/release/desktop/linux"
mkdir -p "$OUT"

test -f "$CLIENT/package.json"
test -d "$CLIENT/node_modules"
cd "$CLIENT"
export PATH="$CLIENT/node_modules/.bin:$PATH"

if ! command -v vp >/dev/null 2>&1; then
  echo "vp not found on PATH; installing vite-plus globally"
  npm install -g vite-plus@1.4.0
fi
command -v vp
vp --version || true

echo "Building RahBaz Linux desktop -> $OUT"
node scripts/build-desktop-artifact.ts \
  --platform linux \
  --target AppImage \
  --arch x64 \
  --verbose \
  --output-dir "$OUT"

echo
echo "Done. Artifacts in $OUT"
ls -la "$OUT"
