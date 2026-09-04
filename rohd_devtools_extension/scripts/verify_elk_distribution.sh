#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

# Verifies the ELK distribution staged for the parent DevTools extension.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="${RELEASE_DIR:-$HOME/release}"
ASSET_ROOT="${1:?Usage: $0 <staged-assets-directory>}"
EXPECTED_ELK_SHA256='cd56bf0ddb7ad2587583461d523fdd974dc56b59efd20cdfee954e1112ff1a49'
SCHEMATIC_VIEWER="$RELEASE_DIR/rohd-schematic-viewer"
CANONICAL_ELK="$SCHEMATIC_VIEWER/assets/js/elk.bundled.js"
CANONICAL_LICENSE="$SCHEMATIC_VIEWER/assets/licenses/elkjs_LICENSES.txt"
CANONICAL_BRIDGE="$SCHEMATIC_VIEWER/js_bridge/elk_layout_only.js"
STAGED_ELK="$ASSET_ROOT/third_party/elkjs/elk.bundled.js"
STAGED_LICENSE="$ASSET_ROOT/third_party/elkjs/LICENSES/elkjs_LICENSES.txt"
STAGED_BRIDGE="$ASSET_ROOT/layout_bridge/elk_layout_only.js"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "Missing $2: $1"
}

for artifact in \
  "$CANONICAL_ELK" \
  "$CANONICAL_LICENSE" \
  "$CANONICAL_BRIDGE" \
  "$STAGED_ELK" \
  "$STAGED_LICENSE" \
  "$STAGED_BRIDGE"; do
  require_file "$artifact" 'ELK distribution artifact'
done

canonical_sha256="$(sha256sum "$CANONICAL_ELK" | awk '{print $1}')"
[[ "$canonical_sha256" == "$EXPECTED_ELK_SHA256" ]] ||
    fail "Canonical ELK hash mismatch: $canonical_sha256"

staged_sha256="$(sha256sum "$STAGED_ELK" | awk '{print $1}')"
[[ "$staged_sha256" == "$EXPECTED_ELK_SHA256" ]] ||
    fail "Staged ELK hash mismatch: $staged_sha256"

cmp -s "$CANONICAL_LICENSE" "$STAGED_LICENSE" ||
    fail 'Staged ELK license notice differs from the canonical notice'
cmp -s "$CANONICAL_BRIDGE" "$STAGED_BRIDGE" ||
    fail 'Staged ELK layout bridge differs from the canonical bridge'

printf 'Verified ELK distribution in %s\n' "$ASSET_ROOT"