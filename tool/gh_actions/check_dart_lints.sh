#!/bin/bash

# Copyright (C) 2023 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# check_dart_lints.sh
# GitHub Actions step: Check for new Dart lints.
#
# 2023 February 23
# Author: Chykon

set -euo pipefail

declare -r file_name='all_lint_rules.yaml'
declare -r reference_file_address='https://raw.githubusercontent.com/dart-lang/linter/main/example/all.yaml'
declare -r reference_file_directory='build/check_dart_lints'
declare -r reference_file="${reference_file_directory}/${file_name}"
declare -r current_file="tool/misc/${file_name}"

mkdir --parents ${reference_file_directory}

curl --fail ${reference_file_address} --output ${reference_file}

if cmp ${current_file} ${reference_file}; then
  echo ''
  echo 'The current file is the latest. No update required.'
  echo ''
else
  declare -r exit_code=${?}
  echo ''
  echo 'Update the base rule set!'
  echo "The latest file can be obtained here: ${reference_file}"
  echo "It can also be obtained from: ${reference_file_address}"
  echo "Replace the contents of the old file located here: ${current_file}"
  echo ''
  exit ${exit_code}
fi
