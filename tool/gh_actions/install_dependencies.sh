#!/bin/bash

# Copyright (C) 2022 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_dependencies.sh
# GitHub Actions step: Install project dependencies.
#
# 2022 October 7
# Author: Chykon
#

### WARNING ###
# The "x" option outputs all script commands. This allows you to track
# the progress of the execution, but MAY REVEAL ANY SECRETS PASSED TO THE SCRIPT!
set -euxo pipefail

#=============#

dart pub get
