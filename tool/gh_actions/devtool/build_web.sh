#!/bin/bash

# Copyright (C) 2024-2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# build_web.sh
# Build DevTool static web.
#
# 2024 January 03
# Author: Yao Jing Quek <yao.jing.quek@intel.com>

set -euo pipefail

cd rohd_devtools_extension

flutter pub get

dart run devtools_extensions build_and_copy --source=. --dest=../extension/devtools

# ---------------------------------------------------------------------------
# Strip service-worker / PWA artefacts.
#
# Why: DevTools extensions are loaded inside an iframe served by the DevTools
# server.  Flutter's default build emits a service worker that aggressively
# caches every asset.  Inside the DevTools iframe this causes two problems:
#   1. The SW intercepts fetch requests and can serve stale cached responses,
#      preventing the extension from picking up new builds.
#   2. The SW registration itself can block or delay the initial iframe load,
#      causing the extension tab to never appear in the DevTools UI.
#
# The fix replaces the caching SW with a tiny stub that unregisters itself,
# removes the PWA manifest, and injects cleanup scripts so any previously
# registered worker is also evicted.
# ---------------------------------------------------------------------------
DEST=../extension/devtools/build

# 1. Replace the full caching service-worker with a self-unregistering stub.
cat > "$DEST/flutter_service_worker.js" << 'SWEOF'
self.addEventListener('install',function(e){self.skipWaiting()});
self.addEventListener('activate',function(e){e.waitUntil(caches.keys().then(function(n){return Promise.all(n.map(function(k){return caches.delete(k)}))}).then(function(){return self.registration.unregister()}).then(function(){return self.clients.matchAll()}).then(function(c){c.forEach(function(cl){cl.navigate(cl.url)})}))});
SWEOF

# 2. Remove PWA manifest (not needed inside DevTools).
rm -f "$DEST/manifest.json"

# 3. Strip manifest link from index.html.
sed -i '/<link rel="manifest"/d' "$DEST/index.html"

# 4. Inject service-worker cleanup script before </body>.
sed -i 's|</body>|<script>if("serviceWorker"in navigator){navigator.serviceWorker.getRegistrations().then(function(r){r.forEach(function(w){w.unregister()})})}</script>\n</body>|' "$DEST/index.html"

# 5. Add iframe-redirect guard in <head> (redirects to debugger/ when opened
#    outside of DevTools).
sed -i '/<head>/a\  <script>if(window.parent===window){window.stop();if("serviceWorker"in navigator){navigator.serviceWorker.getRegistrations().then(function(r){r.forEach(function(w){w.unregister()});if(typeof caches!=="undefined"){caches.keys().then(function(n){n.forEach(function(k){caches.delete(k)})})}})}window.location.replace("debugger/")}</script>' "$DEST/index.html"
