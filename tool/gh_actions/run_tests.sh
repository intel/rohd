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

dart test

# run tests in JS (increase heap size also)
export NODE_OPTIONS="--max-old-space-size=8192"
dart test --platform node