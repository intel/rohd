#!/bin/bash

# Copyright (C) 2022 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# check_folder_tmp_test.sh
# GitHub Actions step: Check folder - tmp_test.
#
# 2022 October 12
# Author: Chykon
#

set -euo pipefail

declare -r folder_name='tmp_test'

# The "tmp_test" folder after performing the tests should be empty.
if [ -d "${folder_name}" ]; then
  output=$(find ${folder_name} | wc --lines | tee)
  if [ "${output}" -eq 1 ]; then
    echo "Success: directory \"${folder_name}\" is empty!"
  else
    echo "Failure: directory \"${folder_name}\" is not empty!"
    exit 1
  fi
else
  echo "Failure: directory \"${folder_name}\" not found!"
  exit 1
fi
