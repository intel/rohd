#!/bin/bash

# Copyright (C) 2022 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# analyze_source.sh
# GitHub Actions step: Analyze project source.
#
# 2022 October 9
# Author: Chykon

set -euo pipefail

dart analyze --fatal-infos
