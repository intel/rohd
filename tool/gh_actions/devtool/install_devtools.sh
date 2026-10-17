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

bash tool/gh_actions/write_local_package_overrides.sh

# ═══════════════════════════════════════════════════════════════════════
#  Build starts here
# ═══════════════════════════════════════════════════════════════════════

cd rohd_devtools_extension

flutter pub get
dart run tool/verify_local_package_resolution.dart

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Building DevTools extension..."
echo "════════════════════════════════════════════════════════════"

flutter build web --pwa-strategy=none --release --no-tree-shake-icons

rm -rf build/web/pkg
cp -R web/pkg build/web/

required_web_artifacts=(
  build/web/canvaskit/canvaskit.js
  build/web/canvaskit/canvaskit.wasm
  build/web/pkg/wellen_bridge.js
  build/web/pkg/wellen_bridge_bg.wasm
)
for required_web_artifact in "${required_web_artifacts[@]}"; do
  if [[ ! -f "$required_web_artifact" ]]; then
    echo "  Expected web artifact was not generated: $required_web_artifact"
    exit 1
  fi
done

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
