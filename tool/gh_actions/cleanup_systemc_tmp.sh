#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# cleanup_systemc_tmp.sh
# GitHub Actions step helper: remove SystemC temporary build caches.
#
# 2026 June
# Author: Desmond Kirkpatrick

set -euo pipefail

declare -r folder_name='tmp_test'

if [ ! -d "${folder_name}" ]; then
  exit 0
fi

find "${folder_name}" -mindepth 1 \
  \( \
    -name 'pch' -o \
    -name 'pch.lock' -o \
    -name 'tmp_sc_*' -o \
    -name 'sc_input_*' -o \
    -name 'Makefile_sc' \
  \) \
  -exec rm -rf {} +

mkdir -p "${folder_name}"