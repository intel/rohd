#!/bin/bash

# Copyright (C) 2024 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# build_web.sh
# Build DevTool static web.
#
# 2024 January 03
# Author: Yao Jing Quek <yao.jing.quek@intel.com>

set -euo pipefail

cd rohd_devtools_extension

flutter pub get

dart run devtools_extensions build_and_copy --source=. --dest=../extension/devtools