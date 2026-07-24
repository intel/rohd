#!/bin/bash

# Copyright (C) 2022-2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# run_tests.sh
# GitHub Actions step: Run project tests.
#
# 2022 October 10
# Author: Chykon

set -euo pipefail

# Run main package tests (auto-discovers test/)
dart test

# Run tests in sub-packages
for pkg in packages/*/; do
  if [ -d "${pkg}test" ]; then
    echo "Running tests in ${pkg}..."
    (cd "$pkg" && dart test)
  fi
done

# Run main package tests in JS (increase heap size for large synthesis tests)
export NODE_OPTIONS="--max-old-space-size=8192"
dart test --platform node