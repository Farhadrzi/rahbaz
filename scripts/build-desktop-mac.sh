#!/usr/bin/env bash
# Build RahBaz macOS DMG (run on a Mac).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/clients/rahbaz-client"
OUT="$ROOT/release/desktop/mac"
ARCH="${ARCH:-arm64}"

if [[ ! -f "$CLIENT/package.json" ]]; then
  echo "RahBaz Client missing at $CLIENT" >&2
  exit 1
fi

if [[ -f "${HOME}/.vite-plus/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.vite-plus/env.sh"
elif [[ -f "${HOME}/.config/vite-plus/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.config/vite-plus/env.sh"
fi

mkdir -p "$OUT"
cd "$CLIENT"
echo "Building RahBaz macOS desktop ($ARCH) -> $OUT"
node scripts/build-desktop-artifact.ts \
  --platform mac \
  --target dmg \
  --arch "$ARCH" \
  --verbose \
  --output-dir "$OUT"

echo
echo "Done. Artifacts in $OUT"
ls -la "$OUT"
