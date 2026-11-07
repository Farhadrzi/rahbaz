#!/bin/bash
# Bootstrap Ubuntu WSL deps and build RahBaz Linux AppImage.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo apt-get install -y \
  build-essential curl ca-certificates pkg-config rsync \
  libsecret-1-dev libgtk-3-dev libnss3 libxss1 libasound2t64 \
  imagemagick ripgrep git python3 xz-utils

# Rust
if ! command -v cargo >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
# shellcheck disable=SC1091
source "$HOME/.cargo/env"
rustup target add x86_64-unknown-linux-gnu

# Node 26 via official tarball (matches monorepo engines)
NODE_VERSION=26.12.1
if ! node -v 2>/dev/null | grep -q "v${NODE_VERSION}"; then
  mkdir -p "$HOME/.local"
  curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" -o /tmp/node.tar.xz
  tar -xJf /tmp/node.tar.xz -C "$HOME/.local"
  export PATH="$HOME/.local/node-v${NODE_VERSION}-linux-x64/bin:$PATH"
fi
export PATH="$HOME/.local/node-v${NODE_VERSION}-linux-x64/bin:$HOME/.cargo/bin:$PATH"
node -v
npm -v

SRC="/mnt/c/Users/farha/.t3/projects/rahbaz"
WORK="$HOME/rahbaz-linux-build"
rm -rf "$WORK"
mkdir -p "$WORK"
# Copy sources without Windows node_modules / heavy caches
rsync -a --ignore-errors \
  --exclude 'node_modules' \
  --exclude '.git' \
  --exclude 'release' \
  --exclude 'auths' \
  --exclude 'config' \
  --exclude 'logs' \
  --exclude '**/target' \
  --exclude '**/.vite' \
  --exclude '**/dist' \
  "$SRC/" "$WORK/" || true

CLIENT="$WORK/clients/rahbaz-client"
OUT="$SRC/release/desktop/linux"
mkdir -p "$OUT"

cd "$CLIENT"
# Install pnpm then project deps (Linux filesystem copy — not Windows node_modules)
if [[ -f package.json ]]; then
  if ! command -v pnpm >/dev/null 2>&1; then
    npm install -g pnpm@10
  fi
  pnpm install --frozen-lockfile || pnpm install
fi
export PATH="$CLIENT/node_modules/.bin:$PATH"
if ! command -v vp >/dev/null 2>&1; then
  npm install -g vite-plus@1.4.0
fi
rm -rf "$CLIENT/.desktop-build.lock"

export T3CODE_DESKTOP_REUSE_RESOURCE_MONITOR=false
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
