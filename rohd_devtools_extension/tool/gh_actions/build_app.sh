#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Builds the standalone ROHD DevTools application for static hosting.
#
# Usage:
#   tool/gh_actions/build_app.sh [base-href]

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
base_href="${1:-}"

if [[ -z "$base_href" ]]; then
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    owner="${GITHUB_REPOSITORY%%/*}"
    repository="${GITHUB_REPOSITORY#*/}"
    if [[ "$repository" == "$owner.github.io" ]]; then
      base_href="/"
    else
      base_href="/$repository/"
    fi
  else
    base_href="/rohd_devtools_extension/"
  fi
fi

if [[ ! "$base_href" =~ ^/([A-Za-z0-9._-]+/)*$ ]]; then
  echo "error: base href must start and end with '/': $base_href" >&2
  exit 64
fi

cd "$repo_root"

make web-release \
  FLUTTER_WEB_BUILD_ARGS="--pwa-strategy=none --base-href=$base_href"

rm -f build/web/flutter_service_worker.js

required_files=(
  build/web/index.html
  build/web/flutter_bootstrap.js
  build/web/main.dart.js
  build/web/assets/AssetManifest.bin
  build/web/assets/layout_bridge/elk_layout_only.js
  build/web/assets/third_party/elkjs/elk.bundled.js
  build/web/pkg/wellen_bridge.js
  build/web/pkg/wellen_bridge_bg.wasm
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    echo "error: expected static app artifact not found: $required_file" >&2
    exit 1
  fi
done

if [[ ! -f build/web/assets/AssetManifest.bin.json &&
      ! -f build/web/assets/AssetManifest.bin ]]; then
  echo "error: expected Flutter asset manifest not found" >&2
  exit 1
fi

if [[ "$(od -An -t x1 -N4 build/web/pkg/wellen_bridge_bg.wasm | tr -d ' \n')" != "0061736d" ]]; then
  echo "error: Wellen artifact does not have the WebAssembly magic bytes." >&2
  exit 1
fi

if grep -Fq 'serviceWorkerSettings: {' build/web/flutter_bootstrap.js; then
  echo "error: Flutter bootstrap unexpectedly registers a service worker." >&2
  exit 1
fi

if ! grep -Fq "<base href=\"$base_href\">" build/web/index.html; then
  echo "error: generated index.html does not use base href $base_href" >&2
  exit 1
fi

touch build/web/.nojekyll

echo "Standalone app ready in build/web/ (base href: $base_href)."
