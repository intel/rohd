#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# check_tmp_test_test.sh
# Test the temporary-output guard with absent/empty directories and leftovers.
# All fixtures are temporary; no repository outputs are removed or SDK commands run.
#
# Usage (from repo root):
#   bash tool/test/check_tmp_test_test.sh
#
# 2026 September 18
# Author: Max Korbel <max.korbel@intel.com>

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
cd "$FIXTURE"

passed=0
run_case() {
  local expected="$1"
  local message="$2"
  local status=0
  bash "$REPO_ROOT/tool/gh_actions/check_tmp_test.sh" > "$FIXTURE/output" 2>&1 || status=$?
  if [[ "$status" -ne "$expected" ]] || ! grep -Fq "$message" "$FIXTURE/output"; then
    cat "$FIXTURE/output"
    echo "Expected exit $expected and '$message', got exit $status." >&2
    exit 1
  fi
  passed=$((passed + 1))
}

run_case 0 'directory "tmp_test" is absent'
[[ ! -e tmp_test ]]

touch leftover.vcd
run_case 1 'VCD files found in the root directory'
rm leftover.vcd

mkdir tmp_test
run_case 0 'directory "tmp_test" is empty'
touch leftover.vcd
run_case 1 'VCD files found in the root directory'
rm leftover.vcd

touch tmp_test/output.txt
run_case 1 'directory "tmp_test" is not empty'
[[ -f tmp_test/output.txt ]]
rm tmp_test/output.txt
touch tmp_test/.hidden
run_case 1 'directory "tmp_test" is not empty'
rm tmp_test/.hidden
mkdir tmp_test/nested
run_case 1 'directory "tmp_test" is not empty'
rmdir tmp_test/nested tmp_test

touch tmp_test
run_case 1 '"tmp_test" exists but is not a directory'
rm tmp_test
ln -s missing-directory tmp_test
run_case 1 '"tmp_test" exists but is not a directory'

echo "$passed temporary-output guard checks passed in isolated fixtures."