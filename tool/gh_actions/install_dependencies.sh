#!/bin/bash

# Copyright (C) 2022-2023 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_dependencies.sh
# GitHub Actions step: Install project dependencies.
#
# 2022 October 7
# Author: Chykon

set -euo pipefail

dart pub get
