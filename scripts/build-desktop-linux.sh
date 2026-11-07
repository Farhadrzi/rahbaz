#!/usr/bin/env bash
# Build RahBaz Linux AppImage (intended for WSL2 or native Linux).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/clients/rahbaz-client"
OUT="$ROOT/release/desktop/linux"
ARCH="${ARCH:-x64}"

if [[ ! -f "$CLIENT/package.json" ]]; then
  echo "RahBaz Client missing at $CLIENT" >&2
  exit 1
fi

# Activate vite-plus if present (Linux installer path varies).
if [[ -f "${HOME}/.vite-plus/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.vite-plus/env.sh"
elif [[ -f "${HOME}/.config/vite-plus/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.config/vite-plus/env.sh"
fi

mkdir -p "$OUT"
cd "$CLIENT"
echo "Building RahBaz Linux desktop ($ARCH) -> $OUT"
node scripts/build-desktop-artifact.ts \
  --platform linux \
  --target AppImage \
  --arch "$ARCH" \
  --verbose \
  --output-dir "$OUT"

echo
echo "Done. Artifacts in $OUT"
ls -la "$OUT"
