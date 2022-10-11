#!/bin/bash

# Copyright (C) 2022 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# verify_formatting.sh
# GitHub Actions step: Verify code formatting.
#
# 2022 October 9
# Author: Chykon
#

set -euo pipefail

dart format --output=none --set-exit-if-changed .
