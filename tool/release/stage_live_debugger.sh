#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Stage the debugger as an independent package outside the checkout.
#
# 2026 November 10
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

if [[ $# -ne 1 || -e "$1" || ! -d "$(dirname "$1")" ]]; then
  echo "Usage: $0 <new-staging-directory>" >&2
  exit 2
fi

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SOURCE="$REPO_ROOT/packages/rohd_live_debugger"
readonly DESTINATION="$1"
readonly DESTINATION_PARENT="$(cd "$(dirname "$DESTINATION")" && pwd -P)"

if [[ "$DESTINATION_PARENT/" == "$REPO_ROOT/"* ]]; then
  echo "Stage the package outside the checkout: $DESTINATION" >&2
  exit 2
fi

if [[ ! -f "$SOURCE/extension/devtools/config.yaml" ||
      ! -f "$SOURCE/extension/devtools/build/index.html" ]]; then
  echo "Build or prepare the rohd_live_debugger DevTools payload first." >&2
  exit 2
fi

mkdir -p "$DESTINATION"
tar -C "$SOURCE" \
  --exclude=./.dart_tool --exclude=./pubspec.lock \
  --exclude=./pubspec_overrides.yaml --exclude=./coverage --exclude=./build \
  -cf - . | tar -C "$DESTINATION" -xf -
awk '$0 != "resolution: workspace"' "$DESTINATION/pubspec.yaml" \
  > "$DESTINATION/pubspec.yaml.tmp"
mv "$DESTINATION/pubspec.yaml.tmp" "$DESTINATION/pubspec.yaml"
echo "Staged rohd_live_debugger in $DESTINATION"
