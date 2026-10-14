#!/bin/bash

# Copyright (C) 2022-2024 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# check_tmp_test.sh
# GitHub Actions step: Check temporary test files.
#
# 2022 October 12
# Author: Chykon

set -euo pipefail

declare -r folder_name='tmp_test'

# The "tmp_test" folder should be absent or empty.
if [[ -d "${folder_name}" ]]; then
  output=$(find "${folder_name}" -mindepth 1 -print -quit)
  if [[ -z "${output}" ]]; then
    echo "Success: directory \"${folder_name}\" is empty!"
  else
    echo "Failure: directory \"${folder_name}\" is not empty!"
    exit 1
  fi
elif [[ -e "${folder_name}" || -L "${folder_name}" ]]; then
  echo "Failure: \"${folder_name}\" exists but is not a directory!"
  exit 1
else
  echo "Success: directory \"${folder_name}\" is absent; no temporary test files!"
fi

# Make sure there are no VCD files in the root directory.
if [[ -n "$(find . -maxdepth 1 -name '*.vcd' -print -quit)" ]]; then
  echo "Failure: VCD files found in the root directory!"
  exit 1
else
  echo "Success: no VCD files found in the root directory!"
fi
