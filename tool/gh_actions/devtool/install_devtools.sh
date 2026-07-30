#!/bin/bash

# Copyright (C) 2024-2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_devtools.sh
# Build the ROHD DevTools extension web artifact:
#   extension/devtools/           – DevTools extension (iframe in Chrome DevTools)
#
# Usage (from repo root):
#   bash tool/gh_actions/devtool/install_devtools.sh
#
# 2024 January 03
# Author: Yao Jing Quek <yao.jing.quek@intel.com>

set -euo pipefail

DEST="../extension/devtools"

# ═══════════════════════════════════════════════════════════════════════
#  Build starts here
# ═══════════════════════════════════════════════════════════════════════

cd rohd_devtools_extension

flutter pub get

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Building DevTools extension..."
echo "════════════════════════════════════════════════════════════"

flutter build web --pwa-strategy=none --release --no-tree-shake-icons

if [ ! -f build/web/canvaskit/canvaskit.js ] || [ ! -f build/web/canvaskit/canvaskit.wasm ]; then
  echo "  Expected CanvasKit artifacts were not generated."
  exit 1
fi

chmod 0755 build/web/canvaskit/canvaskit.js build/web/canvaskit/canvaskit.wasm

# DevTools server serves the extension iframe from $DEST/build/.
rm -rf "$DEST/build"
mkdir -p "$DEST/build"
cp -R build/web/. "$DEST/build/"
rm -f "$DEST/build/manifest.json" "$DEST/build/flutter_service_worker.js"

# Ensure config.yaml exists at $DEST/ (build_and_copy does not generate it).
if [ ! -f "$DEST/config.yaml" ]; then
  echo "  Creating config.yaml..."
  cat > "$DEST/config.yaml" << 'CFGEOF'
name: rohd
issueTracker: https://github.com/intel/rohd/issues
version: 0.0.1
materialIconCodePoint: '0xe1c5'
requiresConnection: false
CFGEOF
fi

# Inject a redirect as the very first <script> in <head>.
# When loaded outside a DevTools iframe, redirect to /debugger/.
echo "  Injecting head-of-page redirect for non-iframe access..."
sed -i 's|<head>|<head>\n  <script>if(window.parent===window){window.location.replace("debugger/")}</script>|' "$DEST/build/index.html"

echo "  Extension deployed to $DEST/ (web assets in $DEST/build/)"
