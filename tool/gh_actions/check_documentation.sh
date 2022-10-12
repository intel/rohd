#!/bin/bash

# Copyright (C) 2022 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# check_documentation.sh
# GitHub Actions step: Check project documentation.
#
# 2022 October 9
# Author: Chykon
#

set -euo pipefail

# Output parsing is required because "dart doc" is not capable of
# signaling a warning with an exit code:
#   https://github.com/dart-lang/dartdoc/issues/2846
#   https://github.com/dart-lang/dartdoc/issues/2907
#   https://github.com/dart-lang/dartdoc/issues/1959

output=$(dart doc --validate-links --dry-run 2>&1 | tee)

# In case of problems, the variable will contain a non-empty string.
if [ -z "${output}" ]; then
  echo 'Documentation check passed!'
else
  echo "${output}"
  exit 1
fi
