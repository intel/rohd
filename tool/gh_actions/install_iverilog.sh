#!/bin/bash

# Copyright (C) 2022 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_iverilog.sh
# GitHub Actions step: Install software - Icarus Verilog.
#
# 2022 October 9
# Author: Chykon
#

set -euo pipefail

sudo apt-get install --yes iverilog
