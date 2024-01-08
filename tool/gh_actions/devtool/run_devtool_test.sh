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

cd rohd_devtools_extension

flutter pub get

flutter test --platform chrome