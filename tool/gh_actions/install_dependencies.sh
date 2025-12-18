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

# If npm is available, install the JS loader dependency used by tests.
if command -v npm >/dev/null 2>&1; then
	echo "Installing Node dependencies (d3-yosys)..."
	npm install d3-yosys
else
	echo "npm not found; skipping Node dependency installation"
fi
