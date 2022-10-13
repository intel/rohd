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

form_bold=$(tput bold)
color_green=$(tput setaf 46)
color_red=$(tput setaf 196)
color_yellow=$(tput setaf 226)
text_reset=$(tput sgr0)

function print_step {
  printf '\n%s\n' "${color_yellow}Step: ${1}${text_reset}"
}

# Notification when the script fails
function trap_error {
  printf '\n%s\n\n' "${form_bold}${color_yellow}Result: ${color_red}FAILURE${text_reset}"
}

trap trap_error ERR

printf '\n%s\n' "${form_bold}${color_yellow}Running local checks...${text_reset}"

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
printf '"which" output: '
if which iverilog; then
  echo 'Icarus Verilog found!'
else
  declare -r exit_code=${?}
  declare -r iverilog_recommended_version='11'
  echo 'Icarus Verilog not found: please install Icarus Verilog'\
    "(iverilog; recommended version: ${iverilog_recommended_version})!"
  exit ${exit_code}
fi

# Run project tests
print_step 'Run project tests'
tool/gh_actions/run_tests.sh

# Check folder - tmp_test
print_step 'Check folder - tmp_test'
tool/gh_actions/check_folder_tmp_test.sh

# Successful script execution notification
printf '\n%s\n\n' "${form_bold}${color_yellow}Result: ${color_green}SUCCESS${text_reset}"
