#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# test_devtools_install.sh
# Smoke-test DevTools discovery of the installed ROHD DevTools extension.
#
# Usage (from repo root, after install_devtools.sh):
#   bash tool/gh_actions/devtool/test_devtools_install.sh [package-root|extension-dir|github-tree-url]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET="${1:-extension/devtools}"
CLEANUP_DIR=""

cleanup() {
  if [[ -n "$CLEANUP_DIR" ]]; then
    rm -rf "$CLEANUP_DIR"
  fi
}
trap cleanup EXIT

fail() {
  echo "  $*" >&2
  exit 1
}

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Testing DevTools extension installation..."
echo "════════════════════════════════════════════════════════════"

if [[ "$TARGET" =~ ^https://github\.com/([^/]+)/([^/]+)/tree/([^/]+)(/(.*))?$ ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
  BRANCH="${BASH_REMATCH[3]}"
  TREE_PATH="${BASH_REMATCH[5]:-}"
  CLEANUP_DIR="$(mktemp -d)"
  ARCHIVE="$CLEANUP_DIR/$REPO-$BRANCH.zip"

  curl -fsSL "https://github.com/$OWNER/$REPO/archive/refs/heads/$BRANCH.zip" -o "$ARCHIVE"
  unzip -q "$ARCHIVE" -d "$CLEANUP_DIR"
  TARGET="$CLEANUP_DIR/$REPO-$BRANCH"
  if [[ -n "$TREE_PATH" ]]; then
    TARGET="$TARGET/$TREE_PATH"
  fi
elif [[ "$TARGET" =~ ^https?:// ]]; then
  fail "Unsupported URL. Expected a GitHub tree URL like https://github.com/intel/rohd/tree/artifacts"
elif [[ "$TARGET" != /* ]]; then
  TARGET="$(pwd)/$TARGET"
fi

if [[ ! -d "$TARGET" ]]; then
  fail "Expected target directory not found: $TARGET"
fi

(cd "$REPO_ROOT/rohd_devtools_extension" && dart run tool/test_devtools_install.dart "$TARGET")

echo "  DevTools extension installation smoke test passed."