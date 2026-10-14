#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# package_vscode.sh
# Build the ROHD VS Code extension using the release packaging steps.
# Installs locked npm dependencies, compiles TypeScript, and validates/packages
# the VSIX locally. Never installs the extension, uploads, or publishes it.
#
# Usage (from any directory):
#   bash tool/package_vscode.sh /absolute/path/to/output.vsix
#
# Requires Node.js and npm; the release workflow uses Node.js 24.
# npm ci replaces the extension's node_modules and packaging updates out/.
#
# 2026 September 18
# Author: Max Korbel <max.korbel@intel.com>

set -euo pipefail

if [[ $# -ne 1 || "$1" != /*.vsix ]]; then
  echo "Usage: $0 /absolute/path/to/output.vsix" >&2
  exit 2
fi

readonly VSIX_PATH="$1"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

for executable in node npm; do
  if ! command -v "$executable" >/dev/null; then
    echo "Required command not found: $executable (release workflow uses Node.js 24)." >&2
    exit 2
  fi
done

if [[ -e "$VSIX_PATH" || -L "$VSIX_PATH" ]]; then
  echo "Refusing to overwrite an existing VSIX: $VSIX_PATH" >&2
  exit 2
fi

mkdir -p "$(dirname "$VSIX_PATH")"
cd "$REPO_ROOT/rohd_extension"
npm ci
npm run package -- --out "$VSIX_PATH"
if [[ ! -s "$VSIX_PATH" ]]; then
  echo "Packaging did not produce a nonempty VSIX: $VSIX_PATH" >&2
  exit 1
fi
echo "VSIX packaged successfully: $VSIX_PATH"