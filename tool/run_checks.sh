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

declare -r iverilog_recommended_version='11'

color_green=$(tput setaf 46)
color_red=$(tput setaf 196)
color_yellow=$(tput setaf 226)
color_reset=$(tput sgr0)

# Notification when the script fails
function trap_error {
  printf '\n%s\n\n' "${color_yellow}Result: ${color_red}FAILURE${color_reset}"
}

function print_step {
  printf '\n%s\n' "${color_yellow}Step: ${1}${color_reset}"
}

trap trap_error ERR

# Install project dependencies
print_step 'Install project dependencies'
tool/gh_actions/install_dependencies.sh

# Verify project formatting
print_step 'Verify project formatting'
tool/gh_actions/verify_formatting.sh

# Analyze project source
print_step 'Analyze project source'
tool/gh_actions/analyze_source.sh

# Check project documentation
print_step 'Check project documentation'
tool/gh_actions/check_documentation.sh

# Check software - Icarus Verilog
print_step 'Check software - Icarus Verilog'
if which iverilog; then
  echo 'Icarus Verilog found!'
else
  echo 'Icarus Verilog not found: please install Icarus Verilog'\
    "(iverilog; recommended version: ${iverilog_recommended_version})!"
  exit 1
fi

# Run project tests
print_step 'Run project tests'
tool/gh_actions/run_tests.sh

# Successful script execution notification
printf '\n%s\n\n' "${color_yellow}Result: ${color_green}SUCCESS${color_reset}"
