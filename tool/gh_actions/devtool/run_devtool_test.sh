#!/bin/bash

# Copyright (C) 2024 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# run_devtool_test.sh
# Run devtool test
#
# 2024 January 03
# Author: Yao Jing Quek <yao.jing.quek@intel.com>

set -euo pipefail

bash tool/gh_actions/write_local_package_overrides.sh
cd rohd_devtools_extension

flutter pub get
dart run tool/verify_local_package_resolution.dart

mapfile -t browser_tests < <(
  find test -type f -name '*_test.dart' \
    ! -path 'test/debugger/*' \
    ! -path 'test/integration/*' | sort
)
flutter test --platform chrome "${browser_tests[@]}"
flutter test
