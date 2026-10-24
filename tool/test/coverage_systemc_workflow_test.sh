#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# coverage_systemc_workflow_test.sh
# Checks coverage CI prepares the required SystemC toolchain.
#
# 2026 October 24
# Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly WORKFLOW="$REPO_ROOT/.github/workflows/coverage.yml"

grep -F "ROHD_REQUIRE_SYSTEMC: '1'" "$WORKFLOW" > /dev/null

systemc_line="$(grep -n -m1 'Install Accellera SystemC' "$WORKFLOW" | cut -d: -f1)"
pch_line="$(grep -n -m1 'Pre-build SystemC PCH and Makefile' "$WORKFLOW" | cut -d: -f1)"
coverage_line="$(grep -n -m1 'Generate coverage and badge' "$WORKFLOW" | cut -d: -f1)"

((systemc_line < pch_line && pch_line < coverage_line))

echo 'Coverage SystemC workflow checks passed.'
