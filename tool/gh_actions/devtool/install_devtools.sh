#!/bin/bash

# Copyright (C) 2024-2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_devtools.sh
# Build all ROHD DevTools web artifacts:
#   extension/devtools/           – DevTools extension (iframe in Chrome DevTools)
#   extension/devtools/debugger/  – Standalone debugger web app
#   extension/devtools/waves/     – Standalone waveform viewer
#   extension/devtools/schematics/ – Standalone schematic viewer
#
# Usage (from repo root):
#   bash tool/gh_actions/devtool/install_devtools.sh
#
# 2024 January 03
# Author: Yao Jing Quek <yao.jing.quek@intel.com>

set -euo pipefail

DEST="../extension/devtools"
WAVE_PKG="rohd-wave-viewer/web/pkg"
STANDALONE_VIEWS=(debugger waves schematics)
WASM_VIEWS=(debugger waves)

# ── Helper: strip service-worker / PWA artifacts from a deployed build ──
#
# Flutter's --pwa-strategy=none still creates an empty service worker file
# that gets registered if a browser has a stale SW cached from a prior visit.
# We replace it with a self-unregistering stub that evicts any old caches,
# remove manifest.json, strip <link rel="manifest">, inject a SW-unregister
# snippet before </body>, and strip serviceWorkerSettings from bootstrap.
strip_sw_artifacts() {
  local dir="$1"
  local name="$2"
  echo "  Stripping SW/PWA artifacts from $name..."

  # Self-unregistering service worker stub
  cat > "$dir/flutter_service_worker.js" << 'SWEOF'
self.addEventListener('install',function(e){self.skipWaiting()});
self.addEventListener('activate',function(e){e.waitUntil(caches.keys().then(function(n){return Promise.all(n.map(function(k){return caches.delete(k)}))}).then(function(){return self.registration.unregister()}).then(function(){return self.clients.matchAll()}).then(function(c){c.forEach(function(cl){cl.navigate(cl.url)})}))});
SWEOF

  rm -f "$dir/manifest.json"
  sed -i '/<link rel="manifest"/d' "$dir/index.html"

  # Inject SW unregistration before </body>
  sed -i 's|</body>|<script>if("serviceWorker"in navigator){navigator.serviceWorker.getRegistrations().then(function(r){r.forEach(function(w){w.unregister()})})}</script>\n</body>|' "$dir/index.html"

  # Strip serviceWorkerSettings from flutter_bootstrap.js
  python3 -c "
import re
p = '$dir/flutter_bootstrap.js'
with open(p) as f: c = f.read()
c = re.sub(r'_flutter\.loader\.load\(\{[^}]*serviceWorkerSettings[^}]*\{[^}]*\}[^}]*\}\);', '_flutter.loader.load();', c, flags=re.DOTALL)
with open(p, 'w') as f: f.write(c)
"
}

# ── Helper: copy WASM pkg into a deployed build ──
copy_wasm_pkg() {
  local dir="$1"
  if [ -d "$WAVE_PKG" ]; then
    echo "  Copying WASM pkg into $(basename "$dir")..."
    rm -rf "$dir/pkg"
    cp -r "$WAVE_PKG" "$dir/pkg"
  elif [ -d "$DEST/build/pkg" ]; then
    echo "  Copying WASM pkg from extension build into $(basename "$dir")..."
    rm -rf "$dir/pkg"
    cp -r "$DEST/build/pkg" "$dir/pkg"
  fi
}

# ── Helper: copy ELK JS assets into a deployed build ──
# build_and_copy / flutter build strips web/ <script>-referenced files;
# restore them from the build output.
copy_elk_assets() {
  local build_dir="$1"
  local deploy_dir="$2"
  echo "  Copying ELK JS assets into $(basename "$deploy_dir")..."
  cp -r "$build_dir/assets/js" "$deploy_dir/assets/" 2>/dev/null || true
  cp "$build_dir/assets/elk_layout_only.js" "$deploy_dir/assets/" 2>/dev/null || true
}

run_widget_hook() {
  local package_dir="$1"
  local route="$2"
  local deploy_dir="$3"
  local output_dir="$4"
  local hook="$package_dir/scripts/devtools_post_build.sh"

  if [ -f "$hook" ]; then
    echo "  Running widget hook for $route..."
    # Hook arguments:
    #   1: deployed directory (under extension/devtools)
    #   2: route name (for logging/branching)
    #   3: package directory
    #   4: build output directory (relative to package directory)
    bash "$hook" "$deploy_dir" "$route" "$package_dir" "$output_dir"
  fi
}

# Generic standalone widget build/deploy helper.
# Args:
#   1: step label (e.g. 3/4)
#   2: display name
#   3: route/deploy directory name
#   4: package directory
#   5: build output directory (relative to package directory)
#   6: copy ELK assets? (yes/no)
#   7: copy WASM pkg? (yes/no)
build_standalone_widget() {
  local step="$1"
  local display_name="$2"
  local route="$3"
  local package_dir="$4"
  local output_dir="$5"
  local include_elk="$6"
  local include_wasm="$7"

  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  $step  Building $display_name..."
  echo "════════════════════════════════════════════════════════════"

  pushd "$package_dir" > /dev/null
  flutter pub get
  flutter build web --release --base-href="/$route/" \
    --pwa-strategy=none \
    --output="$output_dir"
  popd > /dev/null

  rm -rf "$DEST/$route"
  cp -r "$package_dir/$output_dir" "$DEST/$route"

  if [ "$include_elk" = "yes" ]; then
    copy_elk_assets "$package_dir/$output_dir" "$DEST/$route"
  fi

  if [ "$include_wasm" = "yes" ]; then
    copy_wasm_pkg "$DEST/$route"
  fi

  strip_sw_artifacts "$DEST/$route" "$route"
  run_widget_hook "$package_dir" "$route" "$DEST/$route" "$output_dir"

  echo "  $display_name deployed to $DEST/$route/"
}

# ═══════════════════════════════════════════════════════════════════════
#  Build starts here
# ═══════════════════════════════════════════════════════════════════════

cd rohd_devtools_extension

flutter pub get

# Stage JS/JSON assets from rohd-schematic-viewer into assets/
bash scripts/stage_assets.sh

# Copy staged assets into web/assets/ so index.html <script> tags resolve
bash scripts/prepare_web_assets.sh

# ── 0. Generate Flutter Rust Bridge bindings for dart_wellen ────────────
# The extension imports dart_wellen, which imports 'rust/frb_generated.dart'.
# That file is not committed; it is produced by FRB codegen.  Step 1
# (build_and_copy below) compiles the extension and will fail with
# "Target of URI doesn't exist: 'rust/frb_generated.dart'" if these
# bindings are missing on a clean checkout.  `make dart` runs only the
# FRB codegen step (build_dart_wellen_bridge.sh) — no Flutter/WASM build.
FRB_DART="rohd-wave-viewer/packages/dart_wellen/lib/src/rust/frb_generated.dart"
if [ ! -f "$FRB_DART" ]; then
  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  0/4  Generating Flutter Rust Bridge bindings (dart_wellen)..."
  echo "════════════════════════════════════════════════════════════"
  ( cd rohd-wave-viewer && make dart )
fi

# ── 1. Extension build (DevTools iframe) ────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  1/4  Building DevTools extension..."
echo "════════════════════════════════════════════════════════════"

dart run devtools_extensions build_and_copy --source=. --dest="$DEST"

# build_and_copy places web assets in $DEST/build/ — this is the correct
# layout.  DevTools server serves the extension iframe from build/.

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

copy_elk_assets "build/web" "$DEST/build"
copy_wasm_pkg "$DEST/build"
strip_sw_artifacts "$DEST/build" "extension"

# Inject a redirect + SW cleanup as the very first <script> in <head>.
# When loaded outside a DevTools iframe (e.g. by a cached service worker
# or direct navigation), window.stop() aborts all pending resource loads,
# the SW is unregistered, and the browser redirects to /debugger/.
echo "  Injecting head-of-page redirect for non-iframe access..."
sed -i 's|<head>|<head>\n  <script>if(window.parent===window){window.stop();if("serviceWorker"in navigator){navigator.serviceWorker.getRegistrations().then(function(r){r.forEach(function(w){w.unregister()});if(typeof caches!=="undefined"){caches.keys().then(function(n){n.forEach(function(k){caches.delete(k)})})}})}window.location.replace("debugger/")}</script>|' "$DEST/build/index.html"

echo "  Extension deployed to $DEST/ (web assets in $DEST/build/)"

# ── 2. Debugger web app ────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  2/4  Building debugger web app..."
echo "════════════════════════════════════════════════════════════"

flutter build web --release --base-href=/debugger/ \
  --pwa-strategy=none \
  --target=lib/main_standalone.dart \
  --output=build/web_standalone

rm -rf "$DEST/debugger"
cp -r build/web_standalone "$DEST/debugger"

copy_elk_assets "build/web_standalone" "$DEST/debugger"
copy_wasm_pkg "$DEST/debugger"
strip_sw_artifacts "$DEST/debugger" "debugger"

echo "  Debugger deployed to $DEST/debugger/"

# ── 3/4. Standalone widget builds ──────────────────────────────────────
build_standalone_widget \
  "3/4" \
  "wave viewer widget" \
  "waves" \
  "rohd-wave-viewer" \
  "build/web_waves" \
  "no" \
  "yes"

build_standalone_widget \
  "4/4" \
  "schematic viewer widget" \
  "schematics" \
  "rohd-schematic-viewer" \
  "build/web_schematics" \
  "yes" \
  "no"

# ── Deduplicate: symlink build/{waves,schematics,debugger} ──────────────
# DevTools only serves build/ for extensions.  Instead of copying ~106 MB
# of identical files, we patch the top-level viewers to use a relative
# <base href="./"> (works for both the standalone Python server and
# DevTools iframe) and symlink from build/.
echo ""
echo "  Symlinking standalone viewers into build/ for DevTools access..."

for tool_dir in "${STANDALONE_VIEWS[@]}"; do
  if [ -d "$DEST/$tool_dir" ]; then
    # Patch base href to ./ — works in both standalone and DevTools contexts
    sed -i 's|<base href="[^"]*">|<base href="./">|' "$DEST/$tool_dir/index.html"
    rm -rf "$DEST/build/$tool_dir"
    ln -sfn "../$tool_dir" "$DEST/build/$tool_dir"
    echo "    build/$tool_dir/ → ../$tool_dir/  (symlink, base href=./)"
  fi
done

# ── Deduplicate: shared canvaskit/ ──────────────────────────────────────
# Flutter embeds a 26 MB canvaskit/ in every web build.  All copies are
# identical.  Keep build/canvaskit/ as canonical and symlink from viewers.
echo ""
echo "  Deduplicating canvaskit/ (~155 MB saved)..."

for tool_dir in "${STANDALONE_VIEWS[@]}"; do
  if [ -d "$DEST/$tool_dir/canvaskit" ]; then
    rm -rf "$DEST/$tool_dir/canvaskit"
    ln -sfn "../build/canvaskit" "$DEST/$tool_dir/canvaskit"
    echo "    $tool_dir/canvaskit/ → build/canvaskit/  (symlink)"
  fi
done

# ── Deduplicate: shared pkg/ (WASM) ────────────────────────────────────
# The wellen WASM bridge (~1 MB) is copied into multiple viewers.
# Keep build/pkg/ as canonical and symlink from viewers that have it.
echo ""
echo "  Deduplicating pkg/ (WASM)..."

for tool_dir in "${WASM_VIEWS[@]}"; do
  if [ -d "$DEST/$tool_dir/pkg" ]; then
    rm -rf "$DEST/$tool_dir/pkg"
    ln -sfn "../build/pkg" "$DEST/$tool_dir/pkg"
    echo "    $tool_dir/pkg/ → build/pkg/  (symlink)"
  fi
done

# ── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  All builds complete.  Deployed to extension/devtools/:"
echo "    /            - DevTools extension (iframe)"
echo "    /debugger/   - Standalone debugger with DTD/VM connection"
echo "    /waves/      - Standalone waveform viewer"
echo "    /schematics/ - Standalone schematic viewer"
echo "════════════════════════════════════════════════════════════"