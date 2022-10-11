#!/bin/bash

# Copyright (C) 2022 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# run_checks.sh
# Run project checks.
#
# 2022 October 11
# Author: Chykon
#

set -euo pipefail

# Install dependencies
printf '\n%s\n' 'Step: Install dependencies'
tool/gh_actions/install_dependencies.sh

# Verify formatting
printf '\n%s\n' 'Step: Verify formatting'
tool/gh_actions/verify_formatting.sh

# Analyze project source
printf '\n%s\n' 'Step: Analyze project source'
tool/gh_actions/analyze_source.sh

# Check documentation
printf '\n%s\n' 'Step: Check documentation'
tool/gh_actions/check_documentation.sh

# Check Icarus Verilog
printf '\n%s\n' 'Step: Check Icarus Verilog'
if ! which iverilog; then
  echo 'Please install Icarus Verilog (iverilog, recommended version: 11)!'
  exit 1
fi

# Run tests
printf '\n%s\n' 'Step: Run tests'
tool/gh_actions/run_tests.sh

printf '\n%s\n\n' 'Run Checks: SUCCESS'
