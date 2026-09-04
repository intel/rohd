#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# ensure_dart_bindings.sh
# Generates Dart/Rust bridge bindings if they're missing
# Called before any Flutter build to ensure bindings are available
#
# 2026 February
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_DIR="${RELEASE_DIR:-$HOME/release}"
WAVE_VIEWER_DIR="$RELEASE_DIR/rohd-wave-viewer"
BINDINGS_FILE="$WAVE_VIEWER_DIR/packages/dart_wellen/lib/src/rust/frb_generated.dart"

# Check if bindings already exist
if [ -f "$BINDINGS_FILE" ]; then
    echo "[ensure_dart_bindings] Bindings already exist: $BINDINGS_FILE"
    exit 0
fi

echo "[ensure_dart_bindings] Bindings missing, generating from Rust sources..."
cd "$WAVE_VIEWER_DIR"
bash scripts/build_dart_wellen_bridge.sh

if [ -f "$BINDINGS_FILE" ]; then
    echo "[ensure_dart_bindings] ✓ Bindings generated successfully"
else
    echo "[ensure_dart_bindings] ✗ ERROR: Failed to generate bindings"
    exit 1
fi
