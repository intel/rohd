#!/bin/bash

# Copyright (C) 2022-2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# run_tests.sh
# GitHub Actions step: Run project tests.
#
# Usage: tool/gh_actions/run_tests.sh [all|vm|node]
# Defaults to both platforms; CI selects one platform per job.
#
# 2022 October 10
# Author: Chykon

set -euo pipefail

platform="${1:-all}"
if [[ $# -gt 1 || ( "$platform" != all && "$platform" != vm && "$platform" != node ) ]]; then
	echo "Usage: $0 [all|vm|node]" >&2
	exit 2
fi

if [[ "$platform" != node ]]; then
	dart test
fi

if [[ "$platform" != vm ]]; then
	export NODE_OPTIONS="--max-old-space-size=8192"
	dart test --platform node
fi
