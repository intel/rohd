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
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_CONFIG="$ROOT_DIR/.dart_tool/package_config.json"

resolve_package_root() {
    dart "$ROOT_DIR/scripts/resolve_package_root.dart" "$PACKAGE_CONFIG" "$1"
}

DART_WELLEN_DIR="$(resolve_package_root dart_wellen)"
BINDINGS_FILE="$DART_WELLEN_DIR/lib/src/rust/frb_generated.dart"

# Check if bindings already exist
if [ -f "$BINDINGS_FILE" ]; then
    echo "[ensure_dart_bindings] Bindings already exist: $BINDINGS_FILE"
    exit 0
fi

echo "[ensure_dart_bindings] Bindings missing, generating from Rust sources..."
WAVE_VIEWER_DIR="$(resolve_package_root rohd_wave_viewer)"
BUILD_SCRIPT="$WAVE_VIEWER_DIR/scripts/build_dart_wellen_bridge.sh"
if [ ! -f "$BUILD_SCRIPT" ]; then
    echo "[ensure_dart_bindings] ERROR: Cannot generate bindings; the resolved " \
        "Wave Viewer package has no build script: $BUILD_SCRIPT" >&2
    exit 1
fi

cd "$WAVE_VIEWER_DIR"
bash "$BUILD_SCRIPT"

if [ -f "$BINDINGS_FILE" ]; then
    echo "[ensure_dart_bindings] ✓ Bindings generated successfully"
else
    echo "[ensure_dart_bindings] ✗ ERROR: Failed to generate bindings"
    exit 1
fi
