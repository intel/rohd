#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

# Verifies the ELK distribution staged for the parent DevTools extension.

set -euo pipefail

ASSET_ROOT="${1:?Usage: $0 <staged-assets-directory>}"
EXPECTED_ELK_SHA256='cd56bf0ddb7ad2587583461d523fdd974dc56b59efd20cdfee954e1112ff1a49'
SCHEMATIC_VIEWER_ASSETS="$ASSET_ROOT/packages/rohd_schematic_viewer"
STAGED_ELK="$SCHEMATIC_VIEWER_ASSETS/assets/js/elk.bundled.js"
STAGED_LICENSE="$SCHEMATIC_VIEWER_ASSETS/assets/licenses/elkjs_LICENSES.txt"
STAGED_BRIDGE="$SCHEMATIC_VIEWER_ASSETS/js_bridge/elk_layout_only.js"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "Missing $2: $1"
}

for artifact in "$STAGED_ELK" "$STAGED_LICENSE" "$STAGED_BRIDGE"; do
  require_file "$artifact" 'ELK distribution artifact'
done

staged_sha256="$(sha256sum "$STAGED_ELK" | awk '{print $1}')"
[[ "$staged_sha256" == "$EXPECTED_ELK_SHA256" ]] ||
    fail "Staged ELK hash mismatch: $staged_sha256"

printf 'Verified ELK distribution in %s\n' "$ASSET_ROOT"