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
readonly STANDALONE_EXTENSION_DIR="$FIXTURE/standalone package/extension/devtools"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$EXTENSION_DIR/build/assets" "$EXTENSION_DIR/build/canvaskit" "$EXTENSION_DIR/build/dart_wellen"
cat > "$PACKAGE_ROOT/pubspec.yaml" <<'EOF'
name: rohd_live_debugger
environment:
  sdk: ^3.6.0
EOF
cp "$REPO_ROOT/packages/rohd_live_debugger/extension/devtools/config.yaml" "$EXTENSION_DIR/config.yaml"
for asset in index.html flutter_bootstrap.js flutter.js main.dart.js version.json \
  assets/AssetManifest.bin assets/FontManifest.json canvaskit/canvaskit.js canvaskit/canvaskit.wasm \
  dart_wellen/wellen_bridge.js dart_wellen/wellen_bridge_bg.wasm; do
  touch "$EXTENSION_DIR/build/$asset"
done
printf '{"version":"0.1.0"}\n' > "$EXTENSION_DIR/build/version.json"
mkdir -p "$(dirname "$STANDALONE_EXTENSION_DIR")"
cp -R "$EXTENSION_DIR" "$STANDALONE_EXTENSION_DIR"

for target in "$PACKAGE_ROOT" "$EXTENSION_DIR" "$STANDALONE_EXTENSION_DIR"; do
  if ! bash "$REPO_ROOT/tool/gh_actions/devtool/test_devtools_install.sh" "$target" > "$FIXTURE/output" 2>&1; then
    cat "$FIXTURE/output"
    exit 1
  fi
  if [[ "$target" == "$STANDALONE_EXTENSION_DIR" ]]; then
    grep -F 'DevTools loader found extension "rohd_live_debugger" at ' "$FIXTURE/output"
  else
    grep -F "DevTools loader found extension \"rohd_live_debugger\" at $EXTENSION_DIR/build" "$FIXTURE/output"
  fi
done

echo '3 DevTools artifact-discovery checks passed against temporary packages.'

printf '{"version":"0.0.2"}\n' > "$EXTENSION_DIR/build/version.json"
if bash "$REPO_ROOT/tool/gh_actions/devtool/test_devtools_install.sh" "$PACKAGE_ROOT" > "$FIXTURE/output" 2>&1; then
  echo 'A mismatched web build version unexpectedly passed discovery.' >&2
  exit 1
fi
grep -Fq 'Web build version does not match DevTools config' "$FIXTURE/output"
printf '{"version":"0.1.0"}\n' > "$EXTENSION_DIR/build/version.json"

# A stale ignored build alone must not make ROHD provide an extension.
[[ ! -f "$REPO_ROOT/extension/devtools/config.yaml" ]]
! grep -Eq '^[[:space:]]+rohd_live_debugger:' "$REPO_ROOT/pubspec.yaml"
mkdir -p "$FIXTURE/rohd/extension/devtools/build"
printf 'name: rohd\nenvironment:\n  sdk: ^3.6.0\n' > "$FIXTURE/rohd/pubspec.yaml"
touch "$FIXTURE/rohd/extension/devtools/build/index.html"
(
  cd "$REPO_ROOT/rohd_devtools_extension"
  dart run tool/test_devtools_install.dart --expect-absent "$FIXTURE/rohd"
)

# Exercise the installer redirect without rebuilding dependencies or using
# the network.
readonly BUILD_REPO="$FIXTURE/build repo"
mkdir -p "$BUILD_REPO/tool/gh_actions/devtool" \
  "$BUILD_REPO/rohd_devtools_extension/web/dart_wellen" \
  "$BUILD_REPO/packages/rohd_live_debugger/extension/devtools" "$FIXTURE/bin"
cp "$REPO_ROOT/tool/gh_actions/devtool/install_devtools.sh" \
  "$BUILD_REPO/tool/gh_actions/devtool/"
printf '#!/bin/bash\nexit 0\n' > \
  "$BUILD_REPO/tool/gh_actions/write_local_package_overrides.sh"
cat > "$FIXTURE/bin/flutter" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "$1" == build ]]; then
  mkdir -p build/web/canvaskit
  printf '<html><head></head><body></body></html>\n' > build/web/index.html
  touch build/web/canvaskit/canvaskit.js build/web/canvaskit/canvaskit.wasm
fi
EOF
printf '#!/bin/bash\nexit 0\n' > "$FIXTURE/bin/dart"
printf '#!/bin/bash\nexit 0\n' > "$FIXTURE/bin/make"
chmod +x "$FIXTURE/bin/flutter" "$FIXTURE/bin/dart" "$FIXTURE/bin/make"
touch "$BUILD_REPO/rohd_devtools_extension/web/dart_wellen/wellen_bridge.js" \
  "$BUILD_REPO/rohd_devtools_extension/web/dart_wellen/wellen_bridge_bg.wasm"
(
  cd "$BUILD_REPO"
  PATH="$FIXTURE/bin:$PATH" bash tool/gh_actions/devtool/install_devtools.sh
)
grep -Fq 'if(window.parent===window){window.location.replace("https://intel.github.io/rohd/rohd-live-debugger/")}' \
  "$BUILD_REPO/packages/rohd_live_debugger/extension/devtools/build/index.html"
grep -Fxq 'version: 0.1.0' "$BUILD_REPO/packages/rohd_live_debugger/extension/devtools/config.yaml"
cmp "$REPO_ROOT/packages/rohd_live_debugger/extension/devtools/config.yaml" \
  "$BUILD_REPO/packages/rohd_live_debugger/extension/devtools/config.yaml"
[[ "$(awk '/^version: / {print $2}' "$REPO_ROOT/packages/rohd_live_debugger/extension/devtools/config.yaml")" == \
  "$(awk '/^version: / {split($2, version, /[+]/); print version[1]}' "$REPO_ROOT/rohd_devtools_extension/pubspec.yaml")" ]]
echo 'Standalone debugger redirect points to the hosted application.'