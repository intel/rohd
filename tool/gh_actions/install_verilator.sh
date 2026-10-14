#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_verilator.sh
# GitHub Actions step: Install Verilator.
#
# 2026 September 9
# Author: Max Korbel <max.korbel@intel.com>

set -euo pipefail

sudo -n apt-get install --yes verilator build-essential
verilator --version
