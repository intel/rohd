#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_gtkwave.sh
# GitHub Actions step: Install GTKWave and its fst2vcd converter.
#
# 2026 October 12
# Author: ROHD Contributors

set -euo pipefail

sudo -n apt-get update
sudo -n apt-get install --yes gtkwave
command -v fst2vcd
