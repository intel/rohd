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

# Install dependencies
printf '\n%s\n' "${color_yellow}Step: Install dependencies${color_reset}"
tool/gh_actions/install_dependencies.sh

# Verify formatting
printf '\n%s\n' "${color_yellow}Step: Verify formatting${color_reset}"
tool/gh_actions/verify_formatting.sh

# Analyze project source
printf '\n%s\n' "${color_yellow}Step: Analyze project source${color_reset}"
tool/gh_actions/analyze_source.sh

# Check documentation
printf '\n%s\n' "${color_yellow}Step: Check documentation${color_reset}"
tool/gh_actions/check_documentation.sh

# Check Icarus Verilog
printf '\n%s\n' "${color_yellow}Step: Check Icarus Verilog${color_reset}"
if which iverilog; then
  echo 'Icarus Verilog found.'
else
  echo 'Failure: please install Icarus Verilog (iverilog, recommended version: 11)!'
  exit 1
fi

# Run tests
printf '\n%s\n' "${color_yellow}Step: Run tests${color_reset}"
tool/gh_actions/run_tests.sh

# Result
printf '\n%s\n\n' "${color_yellow}Result: ${color_green}SUCCESS${color_reset}"
