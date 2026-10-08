#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# devtools_install_test.sh
# Test discovery of a DevTools extension outside the active checkout, including
# paths with spaces. Uses temporary fixture assets and the real DevTools loader;
# no build, publication, or repository metadata changes are performed.
#
# Usage (after installing the DevTools application's dependencies):
#   bash tool/test/devtools_install_test.sh
#
# 2026 September 18
# Author: Max Korbel <max.korbel@intel.com>

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly FIXTURE="$(mktemp -d)"
readonly PACKAGE_ROOT="$FIXTURE/package with spaces"
readonly EXTENSION_DIR="$PACKAGE_ROOT/extension/devtools"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$EXTENSION_DIR/build/assets" "$EXTENSION_DIR/build/canvaskit"
cp "$REPO_ROOT/extension/devtools/config.yaml" "$EXTENSION_DIR/config.yaml"
for asset in index.html flutter_bootstrap.js flutter.js main.dart.js version.json \
  assets/AssetManifest.bin.json assets/FontManifest.json canvaskit/canvaskit.js canvaskit/canvaskit.wasm; do
  touch "$EXTENSION_DIR/build/$asset"
done

for target in "$PACKAGE_ROOT" "$EXTENSION_DIR"; do
  if ! bash "$REPO_ROOT/tool/gh_actions/devtool/test_devtools_install.sh" "$target" > "$FIXTURE/output" 2>&1; then
    cat "$FIXTURE/output"
    exit 1
  fi
  grep -F "DevTools loader found extension \"rohd\" at $EXTENSION_DIR/build" "$FIXTURE/output"
done

echo '2 DevTools artifact-discovery checks passed against temporary packages.'