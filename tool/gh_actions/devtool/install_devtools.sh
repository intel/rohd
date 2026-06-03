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
  if [ -f "$dir/flutter_bootstrap.js" ]; then
    python3 -c "
import re
p = '$dir/flutter_bootstrap.js'
with open(p) as f: c = f.read()
c = re.sub(r'_flutter\.loader\.load\(\{[^}]*serviceWorkerSettings[^}]*\{[^}]*\}[^}]*\}\);', '_flutter.loader.load();', c, flags=re.DOTALL)
with open(p, 'w') as f: f.write(c)
"
  fi
}

# ═══════════════════════════════════════════════════════════════════════
#  Build starts here
# ═══════════════════════════════════════════════════════════════════════

cd rohd_devtools_extension

flutter pub get

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Building DevTools extension..."
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

strip_sw_artifacts "$DEST/build" "extension"

# Inject a redirect + SW cleanup as the very first <script> in <head>.
# When loaded outside a DevTools iframe (e.g. by a cached service worker
# or direct navigation), window.stop() aborts all pending resource loads,
# the SW is unregistered, and the browser redirects to /debugger/.
echo "  Injecting head-of-page redirect for non-iframe access..."
sed -i 's|<head>|<head>\n  <script>if(window.parent===window){window.stop();if("serviceWorker"in navigator){navigator.serviceWorker.getRegistrations().then(function(r){r.forEach(function(w){w.unregister()});if(typeof caches!=="undefined"){caches.keys().then(function(n){n.forEach(function(k){caches.delete(k)})})}})}window.location.replace("debugger/")}</script>|' "$DEST/build/index.html"

echo "  Extension deployed to $DEST/ (web assets in $DEST/build/)"
