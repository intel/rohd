#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Builds the production DevTools extension against this checkout's ROHD
# packages, then verifies that DevTools discovers the generated artifact.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# Hosted dart_wellen 0.1.1 metadata references a forked producer URL.
# Use this verified bundle until a corrected hosted package is available.
readonly WAVE_VIEWER_BUNDLE_COMMIT="528178830b081c0aca2e6bbb321372d26725fc59"

cd "$REPO_ROOT"

# Consume the producer-distributed bundle for this exact commit. The smoke
# test must not build the viewer's Rust or WebAssembly artifacts.
WAVE_VIEWER_GIT_URL="https://github.com/intel/rohd-wave-viewer.git" \
  WAVE_VIEWER_GIT_REF="$WAVE_VIEWER_BUNDLE_COMMIT" \
  bash tool/devtools/devtools_dev_mode.sh configure-group wave-viewer git

bash tool/gh_actions/devtool/install_devtools.sh
bash tool/gh_actions/devtool/test_devtools_install.sh extension/devtools
