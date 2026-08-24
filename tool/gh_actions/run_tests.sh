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

# Run workspace tests using each package's Dart or Flutter runner.
dart run tool/workspace.dart test

# Run workspace Dart tests in JS (increase heap size for large synthesis tests).
export NODE_OPTIONS="--max-old-space-size=8192"
dart run tool/workspace.dart test-node