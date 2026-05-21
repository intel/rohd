#!/bin/bash

# Copyright (C) 2022-2023 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# run_tests.sh
# GitHub Actions step: Run project tests.
#
# 2022 October 10
# Author: Chykon

set -euo pipefail

# Exclude FFI-dependent tests (dart:ffi unavailable on some CI platforms).
dart test $(find test -name '*_test.dart' ! -name 'systemc_ffi_cosim_test.dart' | sort)

# run tests in JS (increase heap size also)
export NODE_OPTIONS="--max-old-space-size=8192"
dart test --platform node $(find test -name '*_test.dart' ! -name 'systemc_ffi_cosim_test.dart' | sort)