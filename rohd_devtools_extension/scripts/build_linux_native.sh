#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# build_linux_native.sh
# Prepares native assets for Linux build
#
# 2026 January
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_DIR="${RELEASE_DIR:-$HOME/release}"
WAVE_VIEWER_DIR="$RELEASE_DIR/rohd-wave-viewer"

echo "[build-linux] Preparing native assets for Linux build..."

# Generate Dart/Rust bridge bindings first (needed before building Rust code)
echo "[build-linux] Generating Dart/Rust bridge bindings..."
cd "$WAVE_VIEWER_DIR"
bash scripts/build_dart_wellen_bridge.sh

# Build native Rust library for wave viewer
echo "[build-linux] Building Wave Viewer native library..."
cd "$WAVE_VIEWER_DIR"
make rust-native

# Create native_assets directory structure expected by Flutter
echo "[build-linux] Creating native_assets directory structure..."
mkdir -p "$ROOT_DIR/build/native_assets/linux"

# Copy the native library to where Flutter expects it
echo "[build-linux] Copying libwellen_bridge.so to native_assets..."
cp "$WAVE_VIEWER_DIR/rust/wellen_bridge/target/release/libwellen_bridge.so" \
   "$ROOT_DIR/build/native_assets/linux/" || \
   (echo "ERROR: Failed to copy libwellen_bridge.so" && exit 1)

echo "[build-linux] Native assets prepared successfully"
echo "[build-linux] Location: $ROOT_DIR/build/native_assets/linux/libwellen_bridge.so"
