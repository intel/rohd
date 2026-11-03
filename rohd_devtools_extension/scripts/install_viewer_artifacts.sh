#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_viewer_artifacts.sh
# Installs and verifies prebuilt artifacts from the selected dependency.
#
# 2026 February
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
PACKAGE_CONFIG="$WORKSPACE_ROOT/.dart_tool/package_config.json"

resolve_package_root() {
    dart "$ROOT_DIR/scripts/resolve_package_root.dart" "$PACKAGE_CONFIG" "$1"
}

DART_WELLEN_DIR="$(resolve_package_root dart_wellen)"
INSTALLER="$DART_WELLEN_DIR/tool/bridge_artifacts.py"
if [ ! -f "$INSTALLER" ]; then
    echo "[viewer-artifacts] ERROR: Selected dart_wellen has no consumer artifact installer: $INSTALLER" >&2
    echo "Select a viewer revision/package with packaged web artifacts. DevTools does not build dependencies." >&2
    exit 1
fi
python3 "$INSTALLER" install

missing=0
for binding in api.dart frb_generated.dart frb_generated.io.dart frb_generated.web.dart; do
    if [ ! -f "$DART_WELLEN_DIR/lib/src/rust/$binding" ]; then
        echo "[viewer-artifacts] ERROR: Missing packaged artifact: $DART_WELLEN_DIR/lib/src/rust/$binding" >&2
        missing=1
    fi
done
if [ "$missing" -ne 0 ]; then
    echo "[viewer-artifacts] The selected dart_wellen dependency is incomplete." >&2
    echo "Select a package/revision containing the required prebuilt artifacts." >&2
    echo "DevTools does not generate bindings or build Rust dependencies." >&2
    exit 1
fi

echo "[viewer-artifacts] Packaged Dart bindings are available."
