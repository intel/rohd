#!/bin/bash

# Copyright (C) 2023-2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# run_setup.sh
# GitHub Codespaces setup: Setting up the development environment.
#
# 2023 February 5
# Author: Chykon

set -euo pipefail

# Install Flutter and its bundled Dart SDK for the Pub workspace.
bash tool/gh_codespaces/install_flutter.sh

# install_flutter.sh runs in a child process, so its exported PATH does not
# persist here. Re-export the installed SDK before resolving dependencies.
export FLUTTER_ROOT="${FLUTTER_ROOT:-$HOME/flutter}"
export PATH="$FLUTTER_ROOT/bin:$PATH"
if [[ ! -x "$FLUTTER_ROOT/bin/flutter" ]]; then
  echo "Flutter was not found after installation: $FLUTTER_ROOT/bin/flutter" >&2
  exit 1
fi

# Install Pub dependencies.
tool/gh_actions/install_dependencies.sh

# Install Icarus Verilog.
tool/gh_actions/install_iverilog.sh

bash tool/gh_actions/install_verilator.sh

# Install SystemC.
tool/gh_codespaces/install_systemc.sh

# Install Node
tool/gh_actions/install_node.sh