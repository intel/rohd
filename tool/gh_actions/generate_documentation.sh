#!/bin/bash

# Copyright (C) 2022 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# generate_documentation.sh
# GitHub Actions step: Generate project documentation.
#
# 2022 October 10
# Author: Chykon
#

set -euo pipefail

# See script "check_documentation.sh" for a note on processing "dart doc" output.

# The documentation will be placed in the "doc/api" folder.
output=$(dart doc --validate-links 2>&1 | tee)

echo "${output}"

# In case of problems, the searched substring will not be found.
echo "${output}" | grep --silent 'no issues found'
