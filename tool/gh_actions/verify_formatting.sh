#!/bin/bash

# Copyright (C) 2022 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# verify_formatting.sh
# GitHub Actions step: Verify project formatting.
#
# 2022 October 9
# Author: Chykon
#

set -euo pipefail

if dart format --output=none --set-exit-if-changed .; then
  echo 'Format check passed!'
else
  echo 'Format check failed: please format your code (use "dart format .")!'
  exit 1
fi
