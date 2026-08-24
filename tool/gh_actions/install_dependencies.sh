#!/bin/bash

# Copyright (C) 2022-2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_dependencies.sh
# Installs dependencies from the repository root for local development or CI.
# Pub resolves every member of this pub workspace together, and some members
# declare `sdk: flutter`, so Flutter is required to resolve the workspace,
# including the core ROHD package.
#
# 2022 October 7
# Author: Chykon

set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is required to resolve this pub workspace. Pub resolves" >&2
  echo "every workspace member together, and some members declare" >&2
  echo "'sdk: flutter', so 'dart pub get' cannot resolve the workspace" >&2
  echo "without Flutter, even for core-ROHD-only development. Install" >&2
  echo "Flutter (see tool/gh_codespaces/install_flutter.sh) and retry." >&2
  exit 1
fi

flutter pub get
