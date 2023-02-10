#!/bin/bash

# Copyright (C) 2022-2023 Intel Corporation
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

output=$(dart doc --validate-links 2>&1 | tee)

# In case of problems, the searched substring will not be found.
if echo "${output}" | grep --silent 'no issues found'; then
  echo 'Documentation check passed!'
else
  echo "${output}"
  echo 'Documentation failed since some issues were found'
  exit 1
fi
