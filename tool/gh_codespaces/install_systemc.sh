#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_systemc.sh
# GitHub Codespaces setup: Install the SystemC development package.
#
# 2026 August

set -euo pipefail

sudo apt-get update -qq
sudo apt-get install --yes --no-install-recommends libsystemc-dev
