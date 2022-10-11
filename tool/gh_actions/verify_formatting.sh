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

### WARNING ###
# The "x" option outputs all script commands. This allows you to track
# the progress of the execution, but MAY REVEAL ANY SECRETS PASSED TO THE SCRIPT!
set -euxo pipefail

#=============#

dart format --output=none --set-exit-if-changed .
