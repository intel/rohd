#!/bin/bash

# Copyright (C) 2022-2024 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# generate_documentation.sh
# GitHub Actions step: Generate project documentation.
#
# 2022 October 10
# Author: Chykon

set -euo pipefail

# Output parsing is required because "dart doc" is not capable of
# signaling a warning with an exit code:
#   https://github.com/dart-lang/dartdoc/issues/2846
#   https://github.com/dart-lang/dartdoc/issues/2907
#   https://github.com/dart-lang/dartdoc/issues/1959

# Disabling --validate-links due to
#   https://github.com/dart-lang/dartdoc/issues/3584
#   https://github.com/dart-lang/dartdoc/issues/3939
# output=$(dart doc --validate-links 2>&1 | tee)
output=$(dart doc 2>&1 | tee)

# In case of problems, the searched substring will not be found.
if echo "${output}" | grep --silent -e 'no issues found' -e 'Success!'; then
  echo 'Documentation check passed!'
else
  echo "${output}"
  echo 'Documentation failed since some issues were found'
  exit 1
fi
