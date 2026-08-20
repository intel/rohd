#!/bin/bash

# Copyright (C) 2022-2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_dependencies.sh
# Installs dependencies from the repository root for local development or CI.
# Uses Flutter for the full workspace when available, otherwise Dart for core
# ROHD development.
#
# 2022 October 7
# Author: Chykon

set -euo pipefail

if command -v flutter >/dev/null 2>&1; then
  flutter pub get
else
  echo "Flutter is unavailable; resolving the core ROHD package with Dart."
  dart pub get
fi
