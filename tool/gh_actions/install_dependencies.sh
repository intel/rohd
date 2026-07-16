#!/bin/bash

# Copyright (C) 2022-2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_dependencies.sh
# GitHub Actions step: Install project dependencies.
#
# 2026 July
# Author: Chykon

set -euo pipefail

dart pub get

# Install dependencies for sub-packages
for pkg in packages/*/; do
  if [ -f "${pkg}pubspec.yaml" ]; then
    echo "Installing dependencies for ${pkg}..."
    (cd "$pkg" && dart pub get)
  fi
done
