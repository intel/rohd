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

color_green=$(tput setaf 46)
color_yellow=$(tput setaf 226)
color_reset=$(tput sgr0)

function print_step {
  printf '\n%s\n' "${color_yellow}${1}${color_reset}"
}

# Install dependencies
print_step 'Step: Install dependencies'
tool/gh_actions/install_dependencies.sh

# Verify formatting
print_step 'Step: Verify formatting'
tool/gh_actions/verify_formatting.sh

# Analyze project source
print_step 'Step: Analyze project source'
tool/gh_actions/analyze_source.sh

# Check documentation
print_step 'Step: Check documentation'
tool/gh_actions/check_documentation.sh

# Check Icarus Verilog
print_step 'Step: Check Icarus Verilog'
if which iverilog; then
  echo 'Icarus Verilog found.'
else
  echo 'Failure: please install Icarus Verilog (iverilog, recommended version: 11)!'
  exit 1
fi

# Run tests
print_step 'Step: Run tests'
tool/gh_actions/run_tests.sh

# Result
printf '\n%s\n\n' "${color_yellow}Result: ${color_green}SUCCESS${color_reset}"
