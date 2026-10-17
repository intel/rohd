#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Builds the production DevTools extension against this checkout's ROHD
# packages, then verifies that DevTools discovers the generated artifact.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

cd "$REPO_ROOT"

bash tool/gh_actions/devtool/install_devtools.sh
bash tool/gh_actions/devtool/test_devtools_install.sh extension/devtools
