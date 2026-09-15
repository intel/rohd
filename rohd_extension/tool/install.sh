#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# install.sh — Build and install the ROHD VS Code extension.
#
# Usage:
#   ./tool/install.sh          # build + install
#   ./tool/install.sh --skip-build   # install existing .vsix only
#
# Requires: node >= 24, npm, code CLI
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure Node >= 24 is available.
node_major=0
if command -v node &>/dev/null; then
  node_version=$(node --version)
  node_major=${node_version#v}
  node_major=${node_major%%.*}
fi
if (( node_major < 24 )) && [[ -d "$HOME/.nvm/versions/node" ]]; then
  NODE_DIR=$(ls -d "$HOME/.nvm/versions/node"/v24* 2>/dev/null | sort -V | tail -1 || true)
  if [[ -n "$NODE_DIR" ]]; then
    export PATH="$NODE_DIR/bin:$PATH"
    echo "Using node from $NODE_DIR"
  fi
fi

# If nvm is unavailable, obtain a temporary Node 24 runtime through npm.
# Put it first on PATH so npm lifecycle scripts use the same runtime.
node_major=$(node --version 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/' || echo 0)
if (( node_major < 24 )) && command -v npm &>/dev/null; then
  NODE_BIN=$(npm exec --yes --package=node@24 -- node -p "process.execPath")
  export PATH="$(dirname "$NODE_BIN"):$PATH"
  echo "Using temporary Node runtime at $NODE_BIN"
fi

node_ver=$(node --version 2>/dev/null || echo "none")
echo "Node: $node_ver"
node_major=${node_ver#v}
node_major=${node_major%%.*}
if [[ ! "$node_major" =~ ^[0-9]+$ ]] || (( node_major < 24 )); then
  echo "ERROR: Node.js >= 24 is required to package the extension." >&2
  exit 1
fi

VERSION=$(node -p "require('$EXT_DIR/package.json').version")
VSIX="$EXT_DIR/rohd-${VERSION}.vsix"

# ── Build ──
if [[ "${1:-}" != "--skip-build" ]]; then
  echo "── Installing npm dependencies ──"
  cd "$EXT_DIR"
  npm ci --no-audit --no-fund

  echo "── Compiling TypeScript ──"
  npx tsc

  echo "── Packaging VSIX ──"
  rm -f "$EXT_DIR"/rohd-*.vsix
  npm run package
fi

# ── Install ──
if [[ ! -f "$VSIX" ]]; then
  echo "ERROR: $VSIX not found. Run without --skip-build first." >&2
  exit 1
fi

echo "── Installing $VSIX ──"
code --install-extension "$VSIX" --force

echo ""
echo "Done — ROHD extension v${VERSION} installed."
echo "Reload the VS Code window to activate."
