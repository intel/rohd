#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# install.sh — Build and install the ROHD VS Code extension.
#
# Usage:
#   ./tool/install.sh          # build + install
#   ./tool/install.sh --skip-build   # install existing .vsix only
#
# Requires: node ≥ 18, npm, code CLI
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION=$(node -p "require('$EXT_DIR/package.json').version")
VSIX="$EXT_DIR/rohd-${VERSION}.vsix"

# ── Ensure Node ≥ 18 is available ──
if ! command -v node &>/dev/null; then
  if [[ -d "$HOME/.nvm/versions/node" ]]; then
    NODE_DIR=$(ls -d "$HOME/.nvm/versions/node"/v2* 2>/dev/null | sort -V | tail -1)
    [[ -z "$NODE_DIR" ]] && NODE_DIR=$(ls -d "$HOME/.nvm/versions/node"/v1[89]* 2>/dev/null | sort -V | tail -1)
    if [[ -n "$NODE_DIR" ]]; then
      export PATH="$NODE_DIR/bin:$PATH"
      echo "Using node from $NODE_DIR"
    fi
  fi
fi

node_ver=$(node --version 2>/dev/null || echo "none")
echo "Node: $node_ver"

# ── Build ──
if [[ "${1:-}" != "--skip-build" ]]; then
  echo "── Installing npm dependencies ──"
  cd "$EXT_DIR"
  npm install --no-audit --no-fund

  echo "── Compiling TypeScript ──"
  npx tsc

  echo "── Packaging VSIX ──"
  rm -f "$EXT_DIR"/rohd-*.vsix
  echo y | npx @vscode/vsce package --no-dependencies
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
